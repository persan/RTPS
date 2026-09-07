------------------------------------------------------------------------------
--  RTPS.History
--
--  8.2.2 The RTPS HistoryCache and 8.2.3 the RTPS CacheChange, plus the
--  reference-implementation state of 8.4.6 (ChangeForReader,
--  ChangeFromWriter, ReaderProxy, WriterProxy).
--
--  The HistoryCache is the "double-buffer" that decouples the DDS layer
--  from the RTPS protocol machine: DDS 'writes' CacheChanges into it and
--  the RTPS Writer transmits them; the RTPS Reader receives them and DDS
--  'reads' them out.
------------------------------------------------------------------------------

with RTPS.Types;

package RTPS.History is

   use all type RTPS.Types.SequenceNumber_T;

   subtype Sequence_Number is RTPS.Types.SequenceNumber_T;

   ---------------------------------------------------------------------
   --  8.2.2.1 CacheChange
   ---------------------------------------------------------------------

   type Cache_Change is record
      Kind             : RTPS.Types.ChangeKind_T :=
        RTPS.Types.ALIVE;
      --  @kind
      Write_Time       : RTPS.Types.Time_T       := RTPS.Types.TIME_ZERO;
      --  @sourceTimestamp
      SN               : Sequence_Number         := 1;
      --  @sequenceNumber
      Instance_Handle  : RTPS.Types.InstanceHandle_T := 0;
      --  @instanceHandle
      Guid_Prefix      : RTPS.Types.GuidPrefix_T := RTPS.Types.GUIDPREFIX_UNKNOWN;
      --  @writerGuid prefix part (full GUID kept by the owning Writer)
      Entity_Id        : RTPS.Types.EntityId_T   := RTPS.Types.ENTITYID_UNKNOWN;
      Data             : RTPS.Types.Octet_Buffer := null;
      --  serialized payload (opaque to the protocol machine)
      Data_Length      : Natural := 0;
      Is_Key           : Boolean := False;
   end record;

   type Cache_Change_Ref is access all Cache_Change;

   ---------------------------------------------------------------------
   --  8.2.2 The HistoryCache
   ---------------------------------------------------------------------

   type Change_Array is array (1 .. 1024) of Cache_Change_Ref;
   --  Internal ring storage; index type sized by Capacity at run time.

   protected type History_Cache (Capacity : Positive) is
      --  8.2.2.2 add_change
      procedure Add_Change
        (Kind        :        RTPS.Types.ChangeKind_T;
         Write_Time  :        RTPS.Types.Time_T;
         Instance    :        RTPS.Types.InstanceHandle_T;
         Data        :        RTPS.Types.Octet_Buffer;
         Data_Length :        Natural;
         Is_Key      :        Boolean := False;
         Change      :    out Cache_Change_Ref);
      --  Registers a new CacheChange with the next sequence number.

      --  8.2.2.3 remove_change
      procedure Remove_Change (SN : Sequence_Number) with
        Pre => SN >= 1;

      --  8.2.2.4 / 8.2.2.5
      function Get_Seq_Num_Min return Sequence_Number;
      function Get_Seq_Num_Max return Sequence_Number;

      function Find (SN : Sequence_Number) return Cache_Change_Ref;

      function Count return Natural;

      procedure Set_Writer_Guid (P : RTPS.Types.GuidPrefix_T;
                                 E : RTPS.Types.EntityId_T);

   private
      Changes   : Change_Array := (others => null);
      --  Ring of allocated changes; SN-indexed window.  Only the first
      --  Capacity slots are used.
      Head      : Sequence_Number := 1;
      --  Sequence number of the oldest retained change.
      Tail      : Sequence_Number := 0;
      --  Sequence number most recently added.
      Prefix    : RTPS.Types.GuidPrefix_T := RTPS.Types.GUIDPREFIX_UNKNOWN;
      Entity    : RTPS.Types.EntityId_T   := RTPS.Types.ENTITYID_UNKNOWN;
      --  Writer GUID of the owning Writer (set via Set_Writer_Guid).
   end History_Cache;

   type History_Cache_Ref is access all History_Cache;

   Max_Cache_Capacity : constant := 1024;
   --  Maximum History_Cache Capacity; ring storage is statically sized
   --  (Change_Array) and only the first Capacity slots are used.

private

end RTPS.History;