// `mach_task_self_` is a C global that predates Swift concurrency. It never changes.
@preconcurrency import Darwin
import Foundation

/// Raw counters of a process at one moment.
struct ProcessSample {
    /// Total processor time used since the process started, in seconds.
    var cpuTime: TimeInterval
    /// Memory footprint, the figure shown by Activity Monitor, in bytes.
    var memory: UInt64
    /// Highest memory footprint since the process started, in bytes.
    var peakMemory: UInt64?
}

/// Reads the resource usage of Halo and of its child process.
enum ProcessMetrics {
    /// Usage of Halo's own process, through `task_info`.
    static func currentProcess() -> ProcessSample? {
        guard let memory = taskInfo(TASK_VM_INFO, initial: task_vm_info_data_t()),
              let finishedThreads = taskInfo(MACH_TASK_BASIC_INFO, initial: mach_task_basic_info()),
              let liveThreads = taskInfo(TASK_THREAD_TIMES_INFO, initial: task_thread_times_info())
        else { return nil }
        // Finished threads are only counted by the first flavor, running threads by the second.
        let cpuTime = seconds(finishedThreads.user_time) + seconds(finishedThreads.system_time)
            + seconds(liveThreads.user_time) + seconds(liveThreads.system_time)
        return ProcessSample(
            cpuTime: cpuTime,
            memory: memory.phys_footprint,
            peakMemory: memory.ledger_phys_footprint_peak > 0 ? UInt64(memory.ledger_phys_footprint_peak) : nil
        )
    }

    /// Usage of another process of the same user. `task_info` can't read other processes.
    static func process(_ identifier: pid_t) -> ProcessSample? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(identifier, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(usage.ri_user_time) + Double(usage.ri_system_time)
        return ProcessSample(
            cpuTime: ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000,
            memory: usage.ri_phys_footprint,
            peakMemory: nil
        )
    }

    private static func taskInfo<Info>(_ flavor: Int32, initial: Info) -> Info? {
        var info = initial
        var count = mach_msg_type_number_t(MemoryLayout<Info>.stride / MemoryLayout<natural_t>.stride)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(flavor), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private static func seconds(_ time: time_value_t) -> TimeInterval {
        TimeInterval(time.seconds) + TimeInterval(time.microseconds) / 1_000_000
    }
}
