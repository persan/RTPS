------------------------------------------------------------------------------
--  RTPS.History -- body
--
--  Ring-buffer HistoryCache keyed by sequence number.  Sequence numbers
--  are handed out monotonically starting at 1 (8.3.5.4).
------------------------------------------------------------------------------

package body RTPS.History is

   use all type RTPS.Types.SequenceNumber_T;

   protected body History_Cache is

      procedure Add_Change
        (Kind        :        RTPS.Types.ChangeKind_T;
         Write_Time  :        RTPS.Types.Time_T;
         Instance    :        RTPS.Types.InstanceHandle_T;
         Data        :        RTPS.Types.Octet_Buffer;
         Data_Length :        Natural;
         Is_Key      :        Boolean := False;
         Change      :    out Cache_Change_Ref)
      is
         Slot : Natural;
      begin
         if Tail /= 0
           and then Tail - Head + 1 >=
             Sequence_Number (Natural'Min (Capacity, Max_Cache_Capacity))
         then
            --  Overwrite the oldest change (history depth = Capacity).
            Head := Head + 1;
         end if;
         Tail := Tail + 1;
         Slot := Natural ((Tail - 1) mod
                    Sequence_Number (Max_Cache_Capacity)) + 1;
         Changes (Slot) :=
           new Cache_Change'
             (Kind            => Kind,
              Write_Time      => Write_Time,
              SN              => Tail,
              Instance_Handle => Instance,
              Guid_Prefix     => Prefix,
              Entity_Id       => Entity,
              Data            => Data,
              Data_Length     => Data_Length,
              Is_Key          => Is_Key);
         Change := Changes (Slot);
      end Add_Change;

      procedure Remove_Change (SN : Sequence_Number) is
         Slot : Natural;
      begin
         if SN < Head or else SN > Tail then
            return;
         end if;
         Slot := Natural ((SN - 1) mod
                    Sequence_Number (Max_Cache_Capacity)) + 1;
         Changes (Slot) := null;
      end Remove_Change;

      function Get_Seq_Num_Min return Sequence_Number is
      begin
         if Tail = 0 then
            return RTPS.Types.SEQUENCENUMBER_UNKNOWN;
         end if;
         return Head;
      end Get_Seq_Num_Min;

      function Get_Seq_Num_Max return Sequence_Number is
      begin
         if Tail = 0 then
            return RTPS.Types.SEQUENCENUMBER_UNKNOWN;
         end if;
         return Tail;
      end Get_Seq_Num_Max;

      function Find (SN : Sequence_Number) return Cache_Change_Ref is
         Slot : Natural;
      begin
         if SN < Head or else SN > Tail then
            return null;
         end if;
         Slot := Natural ((SN - 1) mod
                    Sequence_Number (Max_Cache_Capacity)) + 1;
         return Changes (Slot);
      end Find;

      function Count return Natural is
      begin
         if Tail = 0 then
            return 0;
         end if;
         return Natural (Tail - Head + 1);
      end Count;

      procedure Set_Writer_Guid
        (P : RTPS.Types.GuidPrefix_T; E : RTPS.Types.EntityId_T)
      is
      begin
         Prefix := P;
         Entity := E;
      end Set_Writer_Guid;

   end History_Cache;

end RTPS.History;