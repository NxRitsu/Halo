// MediaRemoteHelper
//
// Since macOS 15.4, the private MediaRemote framework only returns now playing information to
// entitled processes. `/usr/bin/perl` is one of them, so Halo runs `media-remote.pl`, which loads
// this library and calls `HaloMediaRemoteRun`. The library then streams now playing updates as
// JSON lines on stdout and executes commands read from stdin, one per line:
//
//   play | pause | toggle | next | previous | seek <seconds> | refresh
//
// When MediaRemote is directly accessible, Halo can instead load this library in its own process
// and use `HaloMediaRemoteStart` and `HaloMediaRemoteSendCommand`, with the same messages.
//
// MediaRemote only reports one "now playing" app: the last one that started playing. When that app
// is paused while another one keeps playing (for instance music paused while a web video plays),
// the helper looks for a playing app among all now playing clients, reports it instead, and sends
// commands to it. The per-client functions are undocumented; their signatures were read from the
// MediaRemote binary on macOS 26 and they are only used when all of them can be resolved.
//
// Since macOS 27 a command can no longer target such an app: mediaremoted redirects it to the
// system's now playing app, which is not the app on screen, and refuses to change that app
// ("Operation not permitted"). So on these versions the helper drops the command and reports
// `"controllable": false`, and Halo disables its controls.
//
// Updates are driven by MediaRemote notifications (no polling). In Perl, the process exits when
// stdin is closed, so it never outlives Halo.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRRegisterForNotificationsFunction)(dispatch_queue_t);
typedef void (*MRGetNowPlayingInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFunction)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetNowPlayingClientFunction)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientGetStringFunction)(id);
typedef Boolean (*MRSendCommandFunction)(int, NSDictionary *);
typedef void (*MRSetElapsedTimeFunction)(double);
typedef void (*MRGetNowPlayingClientsFunction)(dispatch_queue_t, void (^)(NSArray *));
typedef int (*MRClientGetProcessIdentifierFunction)(id);
// (client, origin, queue, completion) — a nil origin means this Mac.
typedef void (*MRGetPlaybackStateForClientFunction)(id, id, dispatch_queue_t, void (^)(unsigned int));
// (client, origin, includeArtwork, queue, completion). The completion receives the info without
// its artwork, then an artwork object when requested. `MRMediaRemoteGetNowPlayingInfo` is built on
// this function and merges the two.
typedef void (*MRGetNowPlayingInfoForClientFunction)(id, id, BOOL, dispatch_queue_t, void (^)(NSDictionary *, void *));
typedef CFDataRef (*MRArtworkCopyImageDataFunction)(void *);
// (command, options, origin, client, flags, queue, completion)
typedef Boolean (*MRSendCommandToClientFunction)(int, NSDictionary *, id, id, unsigned long, dispatch_queue_t, void (^)(id));

enum {
    MRCommandPlay = 0,
    MRCommandPause = 1,
    MRCommandTogglePlayPause = 2,
    MRCommandNextTrack = 4,
    MRCommandPreviousTrack = 5,
    MRCommandSeekToPlaybackPosition = 24,
};

static const unsigned int MRPlaybackStatePlaying = 1;

static struct {
    MRRegisterForNotificationsFunction registerForNotifications;
    MRGetNowPlayingInfoFunction getNowPlayingInfo;
    MRGetIsPlayingFunction getIsPlaying;
    MRGetNowPlayingClientFunction getNowPlayingClient;
    MRClientGetStringFunction clientBundleIdentifier;
    MRClientGetStringFunction clientParentBundleIdentifier;
    MRSendCommandFunction sendCommand;
    MRSetElapsedTimeFunction setElapsedTime;
    MRGetNowPlayingClientsFunction getNowPlayingClients;
    MRClientGetProcessIdentifierFunction clientProcessIdentifier;
    MRGetPlaybackStateForClientFunction getPlaybackStateForClient;
    MRGetNowPlayingInfoForClientFunction getNowPlayingInfoForClient;
    MRArtworkCopyImageDataFunction artworkCopyImageData;
    MRSendCommandToClientFunction sendCommandToClient;
} MR;

typedef void (*HaloMediaRemoteEmitFunction)(const char *json, void *context);

static dispatch_queue_t helperQueue;
static HaloMediaRemoteEmitFunction emitFunction;
static void *emitContext;
static NSString *lastArtworkIdentifier;
static NSString *lastArtworkMediaKey;
static uint64_t fetchGeneration;
/// Client reported instead of the system's now playing app, or nil. Commands are sent to it.
static id selectedClient;

static void writeToStandardOutput(const char *json, void *context) {
    (void)context;
    fputs(json, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emit(NSDictionary *message) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (json == nil) {
        return;
    }
    NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    emitFunction(string.UTF8String, emitContext);
}

static void *mediaRemoteHandle;

/// Notification names are exported constants whose value may differ from the symbol name.
static NSString *notificationName(NSString *symbol) {
    CFStringRef *constant = mediaRemoteHandle ? dlsym(mediaRemoteHandle, symbol.UTF8String) : NULL;
    return constant != NULL && *constant != NULL ? (__bridge NSString *)*constant : symbol;
}

static BOOL loadMediaRemote(void) {
    void *handle = mediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (handle == NULL) {
        return NO;
    }
    MR.registerForNotifications = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MR.getNowPlayingInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    MR.getIsPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MR.getNowPlayingClient = dlsym(handle, "MRMediaRemoteGetNowPlayingClient");
    MR.clientBundleIdentifier = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier");
    MR.clientParentBundleIdentifier = dlsym(handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MR.sendCommand = dlsym(handle, "MRMediaRemoteSendCommand");
    MR.setElapsedTime = dlsym(handle, "MRMediaRemoteSetElapsedTime");
    MR.getNowPlayingClients = dlsym(handle, "MRMediaRemoteGetNowPlayingClients");
    MR.clientProcessIdentifier = dlsym(handle, "MRNowPlayingClientGetProcessIdentifier");
    MR.getPlaybackStateForClient = dlsym(handle, "MRMediaRemoteGetPlaybackStateForClient");
    MR.getNowPlayingInfoForClient = dlsym(handle, "MRMediaRemoteGetNowPlayingInfoForClient");
    MR.artworkCopyImageData = dlsym(handle, "MRNowPlayingArtworkCopyImageData");
    MR.sendCommandToClient = dlsym(handle, "MRMediaRemoteSendCommandToClient");
    return MR.registerForNotifications && MR.getNowPlayingInfo && MR.getIsPlaying && MR.sendCommand;
}

static id jsonValue(id value) {
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
        return value;
    }
    if ([value isKindOfClass:NSDate.class]) {
        return @([(NSDate *)value timeIntervalSince1970]);
    }
    return nil;
}

/// Whether a command can reach an app other than the system's now playing app.
static BOOL canTargetClients(void) {
    static NSOperatingSystemVersion firstBlocked = { 27, 0, 0 };
    return ![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:firstBlocked];
}

static void emitNowPlaying(NSDictionary *info, BOOL isPlaying, NSString *bundleIdentifier, NSString *parentBundleIdentifier) {
    if (info.count == 0) {
        lastArtworkIdentifier = nil;
        emit(@{ @"type": @"empty" });
        return;
    }

    NSMutableDictionary *message = [NSMutableDictionary dictionaryWithObject:@"nowPlaying" forKey:@"type"];
    NSDictionary<NSString *, NSString *> *keys = @{
        @"kMRMediaRemoteNowPlayingInfoTitle": @"title",
        @"kMRMediaRemoteNowPlayingInfoArtist": @"artist",
        @"kMRMediaRemoteNowPlayingInfoAlbum": @"album",
        @"kMRMediaRemoteNowPlayingInfoDuration": @"duration",
        @"kMRMediaRemoteNowPlayingInfoElapsedTime": @"elapsed",
        @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @"rate",
        @"kMRMediaRemoteNowPlayingInfoTimestamp": @"timestamp",
    };
    [keys enumerateKeysAndObjectsUsingBlock:^(NSString *infoKey, NSString *messageKey, BOOL *stop) {
        id value = jsonValue(info[infoKey]);
        if (value != nil) {
            message[messageKey] = value;
        }
    }];
    message[@"playing"] = @(isPlaying);
    message[@"controllable"] = @((BOOL)(selectedClient == nil || canTargetClients()));
    if (bundleIdentifier.length > 0) {
        message[@"bundleIdentifier"] = bundleIdentifier;
    }
    if (parentBundleIdentifier.length > 0) {
        message[@"parentBundleIdentifier"] = parentBundleIdentifier;
    }

    // Artwork is only sent when it changes, since it can weigh hundreds of kilobytes. Some apps
    // (Deezer) republish their info every second, briefly without artwork: that doesn't count as
    // a change unless the track is a different one.
    NSString *mediaKey = [NSString stringWithFormat:@"%@|%@|%@", message[@"title"], message[@"artist"], bundleIdentifier];
    if (![mediaKey isEqualToString:lastArtworkMediaKey]) {
        lastArtworkMediaKey = mediaKey;
        lastArtworkIdentifier = nil;
    }
    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
        NSString *identifier = [NSString stringWithFormat:@"%lu-%lu", (unsigned long)artwork.length, (unsigned long)artwork.hash];
        message[@"artworkIdentifier"] = identifier;
        if (![identifier isEqualToString:lastArtworkIdentifier]) {
            message[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            lastArtworkIdentifier = identifier;
        }
    }
    emit(message);
}

static BOOL canQueryClients(void) {
    return MR.getNowPlayingClients && MR.clientProcessIdentifier && MR.getPlaybackStateForClient
        && MR.getNowPlayingInfoForClient && MR.sendCommandToClient && MR.clientBundleIdentifier;
}

static int processIdentifier(id client) {
    return client != nil ? MR.clientProcessIdentifier(client) : 0;
}

static void emitClient(NSDictionary *info, BOOL isPlaying, id client) {
    NSString *bundleIdentifier = client && MR.clientBundleIdentifier ? MR.clientBundleIdentifier(client) : nil;
    NSString *parentBundleIdentifier = client && MR.clientParentBundleIdentifier ? MR.clientParentBundleIdentifier(client) : nil;
    emitNowPlaying(info, isPlaying, bundleIdentifier, parentBundleIdentifier);
}

/// Looks for a client other than `excluded` that is playing. Also reports whether the currently
/// selected client still exists. Calls `completion` on the helper queue.
static void findPlayingClient(id excluded, void (^completion)(id playingClient, id remainingSelectedClient)) {
    MR.getNowPlayingClients(helperQueue, ^(NSArray *clients) {
        dispatch_group_t group = dispatch_group_create();
        __block id playingClient = nil;
        __block id remainingSelectedClient = nil;
        int excludedProcess = processIdentifier(excluded);
        int selectedProcess = processIdentifier(selectedClient);
        for (id client in clients) {
            int process = processIdentifier(client);
            if (process == excludedProcess) {
                continue;
            }
            if (selectedClient != nil && process == selectedProcess) {
                remainingSelectedClient = client;
            }
            dispatch_group_enter(group);
            MR.getPlaybackStateForClient(client, nil, helperQueue, ^(unsigned int state) {
                if (state == MRPlaybackStatePlaying && playingClient == nil) {
                    playingClient = client;
                }
                dispatch_group_leave(group);
            });
        }
        dispatch_group_notify(group, helperQueue, ^{
            completion(playingClient, remainingSelectedClient);
        });
    });
}

static NSDictionary *infoAddingArtwork(NSDictionary *info, void *artwork) {
    if (artwork == NULL || MR.artworkCopyImageData == NULL) {
        return info;
    }
    NSData *data = CFBridgingRelease(MR.artworkCopyImageData(artwork));
    if (data.length == 0) {
        return info;
    }
    NSMutableDictionary *merged = [info mutableCopy];
    merged[@"kMRMediaRemoteNowPlayingInfoArtworkData"] = data;
    return merged;
}

static void fetchNowPlaying(void) {
    MR.getNowPlayingInfo(helperQueue, ^(NSDictionary *info) {
        MR.getIsPlaying(helperQueue, ^(BOOL isPlaying) {
            if (MR.getNowPlayingClient == NULL) {
                emitNowPlaying(info, isPlaying, nil, nil);
                return;
            }
            MR.getNowPlayingClient(helperQueue, ^(id client) {
                if (isPlaying || !canQueryClients()) {
                    selectedClient = nil;
                    emitClient(info, isPlaying, client);
                    return;
                }
                // The system's now playing app is paused (or gone): prefer an app that is playing,
                // then the app shown before, which the user may just have paused from Halo.
                findPlayingClient(client, ^(id playingClient, id remainingSelectedClient) {
                    id other = playingClient ?: remainingSelectedClient;
                    if (other == nil) {
                        selectedClient = nil;
                        emitClient(info, NO, client);
                        return;
                    }
                    MR.getNowPlayingInfoForClient(other, nil, MR.artworkCopyImageData != NULL, helperQueue, ^(NSDictionary *otherInfo, void *artwork) {
                        if (otherInfo.count == 0) {
                            selectedClient = nil;
                            emitClient(info, NO, client);
                            return;
                        }
                        selectedClient = other;
                        emitClient(infoAddingArtwork(otherInfo, artwork), other == playingClient, other);
                    });
                });
            });
        });
    });
}

/// MediaRemote posts several notifications for a single change: coalesce them into one fetch.
static void scheduleFetch(void) {
    uint64_t generation = ++fetchGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), helperQueue, ^{
        if (generation == fetchGeneration) {
            fetchNowPlaying();
        }
    });
}

/// Sends a command to the selected client when there is one, else to the system's now playing app.
/// A command that can't reach the selected client is dropped, so it never acts on another app.
static void sendCommand(int command, NSDictionary *options) {
    if (selectedClient != nil) {
        if (canTargetClients() && MR.sendCommandToClient != NULL) {
            MR.sendCommandToClient(command, options, nil, selectedClient, 0, helperQueue, ^(id result) {});
        }
    } else {
        MR.sendCommand(command, options);
    }
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    if ([command isEqualToString:@"play"]) {
        sendCommand(MRCommandPlay, nil);
    } else if ([command isEqualToString:@"pause"]) {
        sendCommand(MRCommandPause, nil);
    } else if ([command isEqualToString:@"toggle"]) {
        sendCommand(MRCommandTogglePlayPause, nil);
    } else if ([command isEqualToString:@"next"]) {
        sendCommand(MRCommandNextTrack, nil);
    } else if ([command isEqualToString:@"previous"]) {
        sendCommand(MRCommandPreviousTrack, nil);
    } else if ([command isEqualToString:@"seek"] && parts.count == 2) {
        double position = parts[1].doubleValue;
        if (selectedClient != nil) {
            sendCommand(MRCommandSeekToPlaybackPosition, @{ @"kMRMediaRemoteOptionPlaybackPosition": @(position) });
        } else if (MR.setElapsedTime != NULL) {
            MR.setElapsedTime(position);
        }
    } else if ([command isEqualToString:@"refresh"]) {
        fetchNowPlaying();
    }
}

static void readCommands(void) {
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, helperQueue);
    dispatch_source_set_event_handler(source, ^{
        char bytes[1024];
        ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
        if (count <= 0) {
            // Halo closed the pipe (or quit): stop.
            exit(0);
        }
        [buffer appendBytes:bytes length:(NSUInteger)count];
        NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange range;
        while ((range = [buffer rangeOfData:newline options:0 range:NSMakeRange(0, buffer.length)]).location != NSNotFound) {
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, range.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, range.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line.length > 0) {
                handleCommand(line);
            }
        }
    });
    dispatch_resume(source);
    // Keep the source alive for the lifetime of the process.
    static dispatch_source_t retainedSource;
    retainedSource = source;
}

/// Starts observing now playing changes. Messages are passed to `emitter` on a private queue.
/// Returns false when MediaRemote cannot be loaded.
__attribute__((visibility("default")))
bool HaloMediaRemoteStart(HaloMediaRemoteEmitFunction emitter, void *context) {
    if (helperQueue != NULL) {
        return true;
    }
    emitFunction = emitter;
    emitContext = context;
    helperQueue = dispatch_queue_create("halo.media-remote-helper", DISPATCH_QUEUE_SERIAL);
    if (!loadMediaRemote()) {
        return false;
    }
    NSArray<NSString *> *notificationSymbols = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        // Per-player notifications also cover apps that are not the system's now playing app.
        @"kMRMediaRemotePlayerIsPlayingDidChangeNotification",
        @"kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemotePlayerPlaybackStateDidChangeNotification",
    ];
    NSMutableArray<NSString *> *notifications = [NSMutableArray array];
    for (NSString *symbol in notificationSymbols) {
        [notifications addObject:notificationName(symbol)];
    }
    for (NSString *name in notifications) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(helperQueue, ^{ scheduleFetch(); });
        }];
    }
    MR.registerForNotifications(helperQueue);
    dispatch_async(helperQueue, ^{
        emit(@{ @"type": @"ready" });
        fetchNowPlaying();
    });
    return true;
}

/// Executes one command (see the list at the top of this file).
__attribute__((visibility("default")))
void HaloMediaRemoteSendCommand(const char *command) {
    if (helperQueue == NULL || command == NULL) {
        return;
    }
    NSString *line = [NSString stringWithUTF8String:command];
    dispatch_async(helperQueue, ^{ handleCommand(line); });
}

/// Entry point, installed as a Perl XSUB by `media-remote.pl`. The Perl arguments are ignored.
/// Never returns.
__attribute__((visibility("default")))
void HaloMediaRemoteRun(void *perlInterpreter, void *perlCodeValue) {
    (void)perlInterpreter;
    (void)perlCodeValue;
    @autoreleasepool {
        if (!HaloMediaRemoteStart(writeToStandardOutput, NULL)) {
            writeToStandardOutput("{\"type\":\"error\",\"message\":\"MediaRemote framework unavailable\"}", NULL);
            exit(1);
        }
        dispatch_async(helperQueue, ^{ readCommands(); });
    }
    // MediaRemote delivers its notifications on the main run loop.
    CFRunLoopRun();
    exit(0);
}
