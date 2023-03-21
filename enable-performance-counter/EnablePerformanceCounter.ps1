
if (-Not [string]::IsNullOrEmpty($env:enablePerformanceCounter)) {
    if ($($env:enablePerformanceCounter).ToLower() -eq "false") {
        return;
    }
}

$navPerfCounters = [xml]'<PerformanceCategory Id="NavPerformanceCounters" Name="Microsoft Dynamics NAV" Help="Performance counters for Microsoft Dynamics NAV" MultiInstance="yes">
        <PerformanceCounter Name="% Primary key cache hit rate" Type="rawFraction" Help="The percentage of hits in the primary key cache, compared to the total requests to the primary key cache." />
        <PerformanceCounter Name="PrimaryKeyCacheTotalRequestsRawBaseCounter" Type="rawBase" Help="Primary Key Cache Total Requests Counter" />
        <PerformanceCounter Name="# Primary key cache total requests" Type="numberOfItems64" Help="The total number of requests to the primary key cache. The primary key cache contains the results of requests to get a record by using its primary key." />
        <PerformanceCounter Name="% Command cache hit rate" Type="rawFraction" Help="The percentage of hits in the command cache, compared to the total requests to the command cache." />
        <PerformanceCounter Name="CommandCacheTotalRequestsRawBaseCounter" Type="rawBase" Help="Command Cache Total Requests Counter" />
        <PerformanceCounter Name="# Command cache total requests" Type="numberOfItems64" Help="The total number of requests to the command cache. The command cache contains the results of all SQL commands." />
        <PerformanceCounter Name="% Preferred connection cache hit rate" Type="rawFraction" Help="The percentage of hits in the preferred connection cache, compared to the total number of requests." />
        <PerformanceCounter Name="PreferredConnectionCacheTotalRequestsRawBaseCounter" Type="rawBase" Help="Preferred Connection Cache Total Requests Counter" />
        <PerformanceCounter Name="# Preferred connection total requests" Type="numberOfItems64" Help="The total number of requests to the preferred connection cache. The preferred connection cache contains requests from the SQL connection pool that was last used by a Microsoft Dynamics NAV user." />
        <PerformanceCounter Name="% Preferred connection cache command reuse hit rate" Type="rawFraction" Help="The percentage SQL commands reused from a preferred connection, compared to the total number of preferred connection request." />
        <PerformanceCounter Name="PreferredConnectionCacheCommandReuseTotalRequestsRawBaseCounter" Type="rawBase" Help="Preferred Connection Cache Total Requests Counter" />
        <PerformanceCounter Name="# Preferred connection command reuse total requests" Type="numberOfItems64" Help="The total number of requests to reuse a command from the preferred connection." />
        <PerformanceCounter Name="# Open connections" Type="numberOfItems64" Help="The current number of open connections from the Microsoft Dynamics NAV Server instance to Microsoft Dynamics NAV databases on SQL Servers." />
        <PerformanceCounter Name="% Query repositioning rate" Type="rawFraction" Help="The percentage of queries that are re-executed when fetching the query result." />
        <PerformanceCounter Name="QueryRepositioningTotalRequestsRawBaseCounter" Type="rawBase" Help="Query Repositioning Total Requests Counter" />
        <PerformanceCounter Name="% Result set cache hit rate" Type="rawFraction" Help="The percentage of hits in the result set cache, compared to the total requests to the result set cache." />
        <PerformanceCounter Name="ResultSetCacheTotalRequestsRawBaseCounter" Type="rawBase" Help="Result Set Cache Total Requests Counter" />
        <PerformanceCounter Name="# Result set cache total requests" Type="numberOfItems64" Help="The total number of requests to the result set cache. The result set cache contains result sets that are returned from SQL Server." />
        <PerformanceCounter Name="% Calculated fields cache hit rate" Type="rawFraction" Help="The percentage of hits in the calculated fields cache, compared to the total requests to the calculated fields cache." />
        <PerformanceCounter Name="CalculatedFieldsTotalRequestsRawBaseCounter" Type="rawBase" Help="Calculated Fields Total Requests Counter" />
        <PerformanceCounter Name="# Calculated fields cache total requests" Type="numberOfItems64" Help="The total number of requests to the calculated fields cache. The calculated fields cache contains the results of CALCFIELDS Function (Record) calls." />
        <PerformanceCounter Name="Heartbeat time (ms)" Type="numberOfItems32" Help="The time that it takes to complete a single write to a system table. Every 30 seconds, the Microsoft Dynamics NAV Server instance writes a record to indicate that the instance is alive." />
        <PerformanceCounter Name="# Rows in all temporary tables" Type="numberOfItems64" Help="The number of rows in all temporary tables." />
        <PerformanceCounter Name="Soft throttled connections" Type="rateOfCountsPerSecond32" Help="Number of connections that were soft-throttled" />
        <PerformanceCounter Name="Hard throttled connections" Type="rateOfCountsPerSecond32" Help="Number of connections that were hard-throttled" />
        <PerformanceCounter Name="Transient errors" Type="rateOfCountsPerSecond32" Help="Number of transient errors" />
        <PerformanceCounter Name="# Mounted tenants" Type="numberOfItems64" Help="The number of tenants that are mounted on the Microsoft Dynamics NAV Server instance." />
        <PerformanceCounter Name="Server operations/sec" Type="rateOfCountsPerSecond64" Help="The number of operations that have started on the Microsoft Dynamics NAV Server per second. An operation is a call to the Microsoft Dynamics NAV Server instance from a Microsoft Dynamics NAV client to run Microsoft Dynamics NAV objects. SOAP and OData requests are not included." />
        <PerformanceCounter Name="# Active sessions" Type="numberOfItems64" Help="The number of active sessions on the Microsoft Dynamics NAV Server instance. An active session is a connection to the Microsoft Dynamics NAV Server instance from a Microsoft Dynamics NAV client, such as the Microsoft Dynamics NAV Windows client or Microsoft Dynamics NAV Web client, NAS, or Web services." />
        <PerformanceCounter Name="Average server operation time (ms)" Type="averageTimer32" Help="The average duration of server operations in milliseconds." />
        <PerformanceCounter Name="AverageServerOperationTimeBaseCounterName" Type="averageBase" Help="Total server operation" />
        <PerformanceCounter Name="Total # Pending tasks" Type="numberOfItems32" Help="The total number of pending tasks" />
        <PerformanceCounter Name="Total # Running tasks" Type="numberOfItems32" Help="The total number of running tasks" />
        <PerformanceCounter Name="# Running tasks" Type="numberOfItems32" Help="The number of running tasks" />
        <PerformanceCounter Name="# Available tasks" Type="numberOfItems32" Help="The number of available tasks" />
        <PerformanceCounter Name="Maximum # of tasks" Type="numberOfItems32" Help="The maximum number of tasks" />
        <PerformanceCounter Name="# of task errors/sec" Type="rateOfCountsPerSecond32" Help="The number of task errors per second" />
        <PerformanceCounter Name="Average task execution time" Type="averageTimer32" Help="The average task execution time" />
        <PerformanceCounter Name="AverageTaskExecutionTimeBase" Type="averageBase" Help="The time based average task execution" />
        <PerformanceCounter Name="Time (ms) since the list of running tasks last had capacity for new tasks" Type="elapsedTime" Help="The time (ms) since the list of running tasks last had capacity for new tasks" />
        <PerformanceCounter Name="# Open tenant connections" Type="numberOfItems64" Help="The current number of open tenant connections from the Microsoft Dynamics NAV Server instance to Microsoft Dynamics NAV databases on SQL Servers." />
        <PerformanceCounter Name="# Open application connections" Type="numberOfItems64" Help="The current number of open application connections from the Microsoft Dynamics NAV Server instance to the Microsoft Dynamics NAV application database on SQL Servers." />
      </PerformanceCategory>'

$categoryExists = [System.Diagnostics.PerformanceCounterCategory]::Exists($navPerfCounters.PerformanceCategory.Name)

if (-not $categoryExists) {
    $CounterCollection = New-Object System.Diagnostics.CounterCreationDataCollection
    $navPerfCounters.PerformanceCategory.ChildNodes | % {
        $CounterCollection.Add( (New-Object System.Diagnostics.CounterCreationData $_.Name, $_.Help, $_.Type) ) | Out-Null
    }
    $categoryType = [System.Diagnostics.PerformanceCounterCategoryType]::MultiInstance
    [System.Diagnostics.PerformanceCounterCategory]::Create($navPerfCounters.PerformanceCategory.Name, $navPerfCounters.PerformanceCategory.Help, $categoryType, $CounterCollection) | Out-Null
}

