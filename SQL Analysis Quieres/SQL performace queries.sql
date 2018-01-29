SELECT TOP 50 d.object_id, d.database_id, OBJECT_NAME(object_id, database_id) 'proc name', 
d.cached_time, d.last_execution_time, (d.total_elapsed_time/1000000.0) total_elapsed_time, (d.total_elapsed_time/1000000.0)/d.execution_count AS [avg_elapsed_time],
(d.last_elapsed_time/1000000.0) last_elapsed_time, d.execution_count
FROM sys.dm_exec_procedure_stats AS d
ORDER BY [avg_elapsed_time] desc,[total_worker_time] DESC;


SELECT  DB_NAME(fs.database_id) AS [Database Name] ,
        mf.physical_name ,
        io_stall_read_ms ,
        num_of_reads ,
        CAST(io_stall_read_ms / ( 1.0 + num_of_reads ) AS NUMERIC(10, 1)) AS [avg_read_stall_ms] ,
        io_stall_write_ms ,
        num_of_writes ,
        CAST(io_stall_write_ms / ( 1.0 + num_of_writes ) AS NUMERIC(10, 1)) AS [avg_write_stall_ms] ,
        io_stall_read_ms + io_stall_write_ms AS [io_stalls] ,
        num_of_reads + num_of_writes AS [total_io] ,
        CAST(( io_stall_read_ms + io_stall_write_ms ) / ( 1.0 + num_of_reads
                                                          + num_of_writes ) AS NUMERIC(10,
                                                              1)) AS [avg_io_stall_ms]
FROM    sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
        INNER JOIN sys.master_files AS mf WITH ( NOLOCK ) ON fs.database_id = mf.database_id
                                                             AND fs.[file_id] = mf.[file_id]
ORDER BY avg_io_stall_ms DESC
OPTION  ( RECOMPILE );


SELECT  DB_NAME(fs.database_id) AS [Database Name] ,
        mf.physical_name ,
        io_stall_read_ms ,
        num_of_reads ,
        CAST(io_stall_read_ms / ( 1.0 + num_of_reads ) AS NUMERIC(10, 1)) AS [avg_read_stall_ms] ,
        io_stall_write_ms ,
        num_of_writes ,
        CAST(io_stall_write_ms / ( 1.0 + num_of_writes ) AS NUMERIC(10, 1)) AS [avg_write_stall_ms] ,
        io_stall_read_ms + io_stall_write_ms AS [io_stalls] ,
        num_of_reads + num_of_writes AS [total_io] ,
        CAST(( io_stall_read_ms + io_stall_write_ms ) / ( 1.0 + num_of_reads
                                                          + num_of_writes ) AS NUMERIC(10,
                                                              1)) AS [avg_io_stall_ms]
FROM    sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
        INNER JOIN sys.master_files AS mf WITH ( NOLOCK ) ON fs.database_id = mf.database_id
                                                             AND fs.[file_id] = mf.[file_id]
ORDER BY avg_io_stall_ms DESC
OPTION  ( RECOMPILE );


SELECT TOP 10
        wait_type ,
        max_wait_time_ms wait_time_ms ,
        signal_wait_time_ms ,
        wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms ,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER ( ) AS percent_total_waits ,
        100.0 * signal_wait_time_ms / SUM(signal_wait_time_ms) OVER ( ) AS percent_total_signal_waits ,
        100.0 * ( wait_time_ms - signal_wait_time_ms )
        / SUM(wait_time_ms) OVER ( ) AS percent_total_resource_waits
FROM    sys.dm_os_wait_stats
WHERE   wait_time_ms > 0 -- remove zero wait_time
        AND wait_type NOT IN -- filter out additional irrelevant waits
( 'SLEEP_TASK', 'BROKER_TASK_STOP', 'BROKER_TO_FLUSH', 'SQLTRACE_BUFFER_FLUSH',
                                                                'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'LAZYWRITER_SLEEP', 'SLEEP_SYSTEMTASK',
  'SLEEP_BPOOL_FLUSH', 'BROKER_EVENTHANDLER', 'XE_DISPATCHER_WAIT',
  'FT_IFTSHC_MUTEX', 'CHECKPOINT_QUEUE', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
  'BROKER_TRANSMITTER', 'FT_IFTSHC_MUTEX', 'KSOURCE_WAKEUP',
  'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'ONDEMAND_TASK_QUEUE',
  'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT', 'BAD_PAGE_PROCESS',
  'DBMIRROR_EVENTS_QUEUE', 'BROKER_RECEIVE_WAITFOR',
  'PREEMPTIVE_OS_GETPROCADDRESS', 'PREEMPTIVE_OS_AUTHENTICATIONOPS', 'WAITFOR',
  'DISPATCHER_QUEUE_SEMAPHORE', 'XE_DISPATCHER_JOIN', 'RESOURCE_QUEUE' )
ORDER BY wait_time_ms DESC


-- Look at pending I/O requests by file
SELECT DB_NAME(mf.database_id) AS [Database] , mf.physical_name ,r.io_pending , r.io_pending_ms_ticks , r.io_type , fs.num_of_reads , fs.num_of_writes 
FROM sys.dm_io_pending_io_requests AS r INNER JOIN sys.dm_io_virtual_file_stats(NULL, NULL) AS fs ON r.io_handle = fs.file_handle INNER JOIN sys.master_files AS mf ON fs.database_id = mf.database_id
AND fs.file_id = mf.file_id ORDER BY r.io_pending , r.io_pending_ms_ticks DESC 



-- Calculates average stalls per read, per write, and per total input/output
-- for each database file.
SELECT DB_NAME(database_id) AS [Database Name] , file_id , io_stall_read_ms , num_of_reads , CAST(io_stall_read_ms / ( 1.0 + num_of_reads ) AS NUMERIC(10, 1)) AS [avg_read_stall_ms] , io_stall_write_ms , num_of_writes ,
CAST(io_stall_write_ms / ( 1.0 + num_of_writes ) AS NUMERIC(10, 1)) AS [avg_write_stall_ms] , io_stall_read_ms + io_stall_write_ms AS [io_stalls] , num_of_reads + num_of_writes AS [total_io] , CAST(( io_stall_read_ms + io_stall_write_ms ) / ( 1.0 + num_of_reads
+ num_of_writes) AS NUMERIC(10,1)) AS [avg_io_stall_ms]FROM sys.dm_io_virtual_file_stats(NULL, NULL)ORDER BY avg_io_stall_ms DESC ;
