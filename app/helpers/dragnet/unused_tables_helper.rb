# encoding: utf-8
module Dragnet::UnusedTablesHelper

  private

  def unused_tables
    [
        {
            :name  => t(:dragnet_helper_64_name, :default => 'Detection of unused tables'),
            :desc  => t(:dragnet_helper_64_desc, :default =>'Tables never used for selections may be questioned for their right to exist.
This includes tables that were written, but never read.
'),
            :sql=> "SELECT /* DB-Tools Ramm Nicht genutzte Tabellen */ o.*, sz.MBytes
                      FROM ( SELECT /*+ NO_MERGE */ 'TABLE' Object_Type, Owner, Table_Name Object_Name
                             FROM   DBA_Tables
                             WHERE  IOT_TYPE IS NULL AND Temporary='N'
                             UNION ALL
                             SELECT /*+ NO_MERGE */ 'INDEX' Object_Type, Owner, Index_Name Object_Name
                             FROM   DBA_Indexes
                             WHERE  Index_Type = 'IOT - TOP'
                           ) o
                      LEFT OUTER JOIN
                           (
                             SELECT /*+ NO_MERGE PARALLEL(p,2) FULL(p) PARALLEL(s,2) FULL(s) PARALLEL(t,2) FULL(t)*/
                                    DISTINCT p.Object_Type, p.Object_Owner, p.Object_Name
                             FROM   DBA_Hist_SQL_Plan p
                             JOIN   DBA_Hist_SQLStat s    ON  s.DBID            = p.DBID
                                                          AND s.SQL_ID          = p.SQL_ID
                                                          AND s.Plan_Hash_Value = p.Plan_Hash_Value
                             JOIN   DBA_Hist_SnapShot ss  ON  ss.DBID      = s.DBID
                                                          AND ss.Snap_ID = s.Snap_ID
                                                          AND ss.Instance_Number = s.Instance_Number
                             JOIN   DBA_Hist_SQLText t    ON  t.DBID   = p.DBID AND t.SQL_ID = p.SQL_ID
                             WHERE  ss.Begin_Interval_Time > SYSDATE-?
                             AND    t.SQL_Text NOT LIKE '%dbms_stats cursor_sharing_exact%' /* DBMS-Stats-Statement */
                             AND    (UPPER(t.SQL_Text) LIKE 'SELECT%' OR UPPER(t.SQL_Text) LIKE 'WITH%')
                             UNION
                             SELECT /*+ NO_MERGE */ DISTINCT p.Object_Type, p.Object_Owner, p.Object_Name
                             FROM   gv$SQL_Plan p
                             JOIN   gv$SQLArea s ON (s.Inst_ID=p.Inst_ID AND s.SQL_ID=p.SQL_ID AND s.Plan_Hash_Value=p.Plan_Hash_Value)
                             WHERE  s.Last_Active_Time > SYSDATE-?
                             AND    s.SQL_FullText NOT LIKE '%dbms_stats cursor_sharing_exact%' /* DBMS-Stats-Statement */
                             AND    (UPPER(s.SQL_Text) LIKE 'SELECT%' OR UPPER(s.SQL_Text) LIKE 'WITH%')
                           ) used ON used.Object_Owner = o.Owner AND used.Object_Name = o.Object_Name
                      LEFT OUTER JOIN (SELECT Segment_Name, Owner, SUM(bytes)/(1024*1024) MBytes
                                       FROM   DBA_SEGMENTS
                                       GROUP BY Segment_Name, Owner
                                      ) sz ON sz.SEGMENT_NAME = o.Object_Name AND sz.Owner = o.Owner
                      WHERE  used.Object_Owner IS NULL
                      AND    used.Object_Name IS NULL
                      AND    o.Owner NOT IN ('SYS', 'SYSTEM', 'WMSYS', 'OUTLN', 'MDSYS', 'OLAPSYS', 'EXFSYS', 'DBSNMP', 'SYSMAN', 'XDB', 'CTXSYS', 'DMSYS')
                      ORDER BY sz.MBytes DESC NULLS LAST",
            :parameter=>[{:name=> t(:dragnet_helper_64_param_1_name, :default=>'Number of days backward in AWR-Historie for SQL'), :size=>8, :default=>8, :title=> t(:dragnet_helper_64_param_1_hint, :default=>'Number of days backward for evaluation of AWR-history regarding match in SQL-text')},
                         {:name=> t(:dragnet_helper_64_param_2_name, :default=>'Number of days backward in AWR-Historie for Plan'), :size=>8, :default=>8, :title=> t(:dragnet_helper_64_param_2_hint, :default=>'Number of days backward for evaluation of AWR-history regarding existence in explain-plan')}]
        },
        {
            :name  => t(:dragnet_helper_65_name, :default=>'Missing housekeeping for mass data'),
            :desc  => t(:dragnet_helper_65_desc, :default=>'For many constellations it is essential to remove not productive used aged data from the system m System.
If last analyze table was far enough in history this selection may help to detect gaps in housekeeping.
Stated here are inserts and updates since last GATHER_TABLE_STATS for tables without any delete operations.
'),
            :sql=> "SELECT /* DB-Tools Ramm Housekeeping*/
                             m.Table_Owner, m.Table_Name, m.TimeStamp, t.Last_analyzed,
                             ROUND(m.Timestamp - t.Last_Analyzed, 2) Tage_nach_Analyze,
                             m.Inserts, m.Updates, m.Deletes, m.Truncated, m.Drop_Segments
                      FROM   (SELECT Table_Owner, Table_Name, MAX(Timestamp) Timestamp,
                                     SUM(Inserts) Inserts, SUM(Updates) Updates, SUM(Deletes) Deletes,
                                     MAX(Truncated) Truncated, SUM(Drop_Segments) Drop_Segments
                              FROM sys.DBA_Tab_Modifications
                              GROUP BY Table_Owner, Table_Name
                             ) m
                      JOIN   DBA_Tables t ON t.Owner = m.Table_Owner AND t.Table_Name = m.Table_Name
                      WHERE m.Deletes = 0 AND m.Truncated = 'NO'
                      ORDER BY m.Inserts+m.Updates+m.Deletes DESC NULLS LAST",
        },
        {
            :name  => t(:dragnet_helper_66_name, :default=>'Detection of not used columns (all values = NULL)'),
            :desc  => t(:dragnet_helper_66_desc, :default=>'Unused columns with only NULL-values Spalten can possibly be removed.
Each NULL-value of a record claims one byte if not all subsequent columns of that record are also NULL.
Starting from 11g you can use virtual columns instead if this table structure is precondition (SAP etc.).
'),
            :sql=> "SELECT /* DB-Tools Ramm  Spalten mit komplett  NULL-Values */
                             c.Owner, c.Table_Name, c.Column_Name, t.Num_Rows, c.Num_Nulls, c.Num_Distinct
                      FROM   DBA_Tab_Columns c
                      JOIN   DBA_Tables t ON t.Owner = c.Owner AND t.Table_Name = c.Table_Name
                      WHERE  c.Num_Nulls = t.Num_Rows
                      AND    t.Num_Rows  > 0   -- Tabelle enthaelt auch Daten
                      AND    c.Owner NOT IN ('SYS', 'SYSTEM', 'WMSYS', 'SYSMAN', 'MDSYS')
                      ORDER BY t.Num_Rows DESC NULLS LAST",
        },
        {
            :name  => t(:dragnet_helper_67_name, :default=>'Detection of less informative columns'),
            :desc  => t(:dragnet_helper_67_desc, :default=>'For columns of large tables with less DISTINCT-values meaning can be questioned.
May be it their value is redundant to other columns of that table. In this case you can extract this column as separate master-data table with n:1-relation (normalization).
'),
            :sql=> "SELECT /* DB-Tools Ramm Spalten mit wenig Distinct-Values */
                             c.Owner, c.Table_Name, c.Column_Name, t.Num_Rows, c.Num_Nulls, c.Num_Distinct,
                             ROUND((c.Avg_Col_Len*(Num_Rows-Num_Nulls)+Num_Nulls)/(1024*1024),2) Megabyte
                      FROM   DBA_Tab_Columns c
                      JOIN   DBA_Tables t ON t.Owner = c.Owner AND t.Table_Name = c.Table_Name
                      WHERE  NVL(c.Num_Distinct,0) != 0
                      AND    NVL(t.Num_Rows,0) > ?
                      AND    c.Owner NOT IN ('SYS', 'SYSTEM', 'WMSYS')
                      ORDER BY c.Num_Distinct, t.Num_Rows DESC NULLS LAST",
            :parameter=>[{:name=>t(:dragnet_helper_param_minimal_rows_name, :default=>'Minimum number of rows in table'), :size=>8, :default=>100000, :title=>t(:dragnet_helper_param_minimal_rows_hint, :default=>'Minimum number of rows in table for consideration in selection')}]
        },
        {
            :name  => t(:dragnet_helper_68_name, :default=>'Unused marked but not physical deleted columns'),
            :desc  => t(:dragnet_helper_68_desc, :default=>'For as unused marked columns it may be worth to reorganize the table by ALTER TABLE DROP UNSED COLUMNS or recreation of table.
'),
            :sql=> 'SELECT /* DB-Tools Ramm Unused gesetzte Spalten ohne ALTER TABLE DROP UNUSED COLUMNS*/ cs.*, t.Num_Rows
                      FROM   DBA_Unused_Col_Tabs cs
                      JOIN   DBA_Tables t ON t.Owner = cs.Owner AND t.Table_Name = cs.Table_Name
                      ORDER BY t.Num_Rows*cs.Count DESC NULLS LAST',
        },
        {
            :name  => 'Dropped tables in recycle bin',
            :desc  => "Use 'PURGE RECYCLEBIN' to free space of dropped tables from recycle bin",
            :sql=> "SELECT /* Panorama-Tool Ramm */ *
                      FROM   DBA_Tables
                      WHERE  Dropped = 'YES'
                      ORDER BY Num_Rows DESC NULLS LAST",
        },

    ]
  end # unused_tables

end