// cancel_task.cdc
// Cancel a scheduled agent task.

import "AgentScheduler"

transaction(taskId: UInt64) {
    prepare(signer: auth(Storage) &Account) {
        let scheduler = signer.storage.borrow<auth(AgentScheduler.Cancel) &AgentScheduler.Scheduler>(
            from: AgentScheduler.SchedulerStoragePath
        ) ?? panic("Scheduler not found.")

        let canceled = scheduler.cancelTask(taskId: taskId)
        if canceled {
            log("Task ".concat(taskId.toString()).concat(" canceled"))
        } else {
            log("Task ".concat(taskId.toString()).concat(" not found"))
        }
    }
}
