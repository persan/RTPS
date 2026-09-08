------------------------------------------------------------------------------
--  RTPS.Proto -- body: proxy window-state operations
--
--  The ReaderProxy and WriterProxy keep their per-sequence-number
--  status in a window [First_SN .. Last_SN] with a parallel status
--  array.  All operations below map the pseudocode of 8.4.7.5 /
--  8.4.10.4 onto that window.
------------------------------------------------------------------------------

package body RTPS.Proto is

   use all type Types.Octet;

   ---------------------------------------------------------------------
   --  GUID helpers
   ---------------------------------------------------------------------

   function GUID_Equal (L, R : Types.GUID_T) return Boolean is
   begin
      for K in L.Guid_Prefix'Range loop
         if L.Guid_Prefix (K) /= R.Guid_Prefix (K) then
            return False;
         end if;
      end loop;
      for K in L.Entity_Id'Range loop
         if L.Entity_Id (K) /= R.Entity_Id (K) then
            return False;
         end if;
      end loop;
      return True;
   end GUID_Equal;

   ---------------------------------------------------------------------
   --  ReaderProxy operations (Table 8.56)
   ---------------------------------------------------------------------

   function Window_Index (P : ReaderProxy; SN : Types.SequenceNumber_T)
     return Natural
   is (Natural (SN - P.First_SN));

   procedure Acked_Changes_Set
     (P : in out ReaderProxy; Committed_SN : Types.SequenceNumber_T)
   is
      Idx : Natural;
      Last_Idx : Natural;
   begin
      if P.Status = null or else P.Last_SN < P.First_SN then
         return;
      end if;
      if Committed_SN > P.Last_SN then
         Last_Idx := Window_Index (P, P.Last_SN);
      else
         Last_Idx := Window_Index (P, Committed_SN);
      end if;
      for K in 0 .. Last_Idx loop
         Idx := K;
         if P.Status.all (Idx) = UNSENT
           or else P.Status.all (Idx) = UNACKNOWLEDGED
           or else P.Status.all (Idx) = REQUESTED
         then
            P.Status.all (Idx) := ACKNOWLEDGED;
         end if;
      end loop;
      --  Track the acked high-water mark.
      if Committed_SN > P.Acked_Up_To then
         P.Acked_Up_To := Committed_SN;
      end if;
   end Acked_Changes_Set;

   procedure Requested_Changes_Set
     (P : in out ReaderProxy; SN : Types.SequenceNumber_T)
   is
      Idx : Natural;
   begin
      if P.Status = null then
         return;
      end if;
      if SN < P.First_SN or else SN > P.Last_SN then
         return;
      end if;
      Idx := Window_Index (P, SN);
      --  Only UNSENT/UNACKNOWLEDGED transitions to REQUESTED.
      if P.Status.all (Idx) = UNSENT
        or else P.Status.all (Idx) = UNACKNOWLEDGED
      then
         P.Status.all (Idx) := REQUESTED;
         P.Req_Count := P.Req_Count + 1;
         if P.Req_Count = 1
           or else SN < P.Req_Min_SN
         then
            P.Req_Min_SN := SN;
         end if;
         if SN > P.Highest_Req_SN then
            P.Highest_Req_SN := SN;
         end if;
      end if;
   end Requested_Changes_Set;

   function Next_Requested_SN (P : ReaderProxy) return Types.SequenceNumber_T
   is
      use type Types.SequenceNumber_T;
      Idx : Natural;
   begin
      if P.Req_Count = 0 or else P.Status = null then
         return 0;
      end if;
      --  Scan from the tracked minimum; at most the window size.
      declare
         Start : Types.SequenceNumber_T :=
           (if P.Req_Min_SN >= P.First_SN then P.Req_Min_SN else P.First_SN);
         SN    : Types.SequenceNumber_T := Start;
      begin
         while SN <= P.Last_SN loop
            Idx := Window_Index (P, SN);
            if P.Status.all (Idx) = REQUESTED then
               return SN;
            end if;
            SN := SN + 1;
         end loop;
      end;
      return 0;
   end Next_Requested_SN;

   function Next_Unsent_SN (P : ReaderProxy) return Types.SequenceNumber_T is
      use type Types.SequenceNumber_T;
      SN : Types.SequenceNumber_T := P.First_SN;
      Idx : Natural;
   begin
      if P.Status = null then
         return 0;
      end if;
      while SN <= P.Last_SN loop
         Idx := Window_Index (P, SN);
         if P.Status.all (Idx) = UNSENT then
            return SN;
         end if;
         SN := SN + 1;
      end loop;
      return 0;
   end Next_Unsent_SN;

   function Unacked_Count (P : ReaderProxy) return Natural is
      use type Types.SequenceNumber_T;
      SN    : Types.SequenceNumber_T := P.First_SN;
      Count : Natural := 0;
      Idx   : Natural;
   begin
      if P.Status = null then
         return 0;
      end if;
      while SN <= P.Last_SN loop
         Idx := Window_Index (P, SN);
         if P.Status.all (Idx) = UNACKNOWLEDGED
           or else P.Status.all (Idx) = UNSENT
           or else P.Status.all (Idx) = REQUESTED
         then
            Count := Count + 1;
         end if;
         SN := SN + 1;
      end loop;
      return Count;
   end Unacked_Count;

   function Requested_Count (P : ReaderProxy) return Natural is
   begin
      return P.Req_Count;
   end Requested_Count;

   ---------------------------------------------------------------------
   --  WriterProxy operations (Table 8.68)
   ---------------------------------------------------------------------

   procedure Missing_Changes_Update
     (P : in out WriterProxy; Last_Available_SN : Types.SequenceNumber_T)
   is
      use type Types.SequenceNumber_T;
      SN  : Types.SequenceNumber_T;
      Idx : Natural;
   begin
      if P.Status = null then
         return;
      end if;
      if Last_Available_SN > P.Last_SN then
         --  Grow conceptually: the writer announced SNs beyond our
         --  window; extend the window.
         P.Last_SN := Last_Available_SN;
      end if;
      SN := P.First_SN;
      while SN <= Last_Available_SN and then SN <= P.Last_SN loop
         Idx := Natural (SN - P.First_SN);
         if P.Status.all (Idx) = UNKNOWN then
            P.Status.all (Idx) := MISSING;
         end if;
         SN := SN + 1;
      end loop;
   end Missing_Changes_Update;

   procedure Lost_Changes_Update
     (P : in out WriterProxy; First_Available_SN : Types.SequenceNumber_T)
   is
      use type Types.SequenceNumber_T;
      SN  : Types.SequenceNumber_T;
      Idx : Natural;
   begin
      if P.Status = null then
         return;
      end if;
      SN := P.First_SN;
      while SN < First_Available_SN and then SN <= P.Last_SN loop
         Idx := Natural (SN - P.First_SN);
         if P.Status.all (Idx) = UNKNOWN
           or else P.Status.all (Idx) = MISSING
         then
            P.Status.all (Idx) := LOST;
         end if;
         SN := SN + 1;
      end loop;
      --  Advance the window base past the lost range.
      if First_Available_SN > P.First_SN then
         P.First_SN := First_Available_SN;
      end if;
   end Lost_Changes_Update;

   procedure Received_Change_Set
     (P : in out WriterProxy; SN : Types.SequenceNumber_T)
   is
      use type Types.SequenceNumber_T;
      Idx : Natural;
   begin
      if P.Status = null then
         return;
      end if;
      if SN < P.First_SN or else SN > P.Last_SN then
         return;
      end if;
      Idx := Natural (SN - P.First_SN);
      if P.Status.all (Idx) /= RECEIVED then
         P.Status.all (Idx) := RECEIVED;
      end if;
   end Received_Change_Set;

   procedure Irrelevant_Change_Set
     (P : in out WriterProxy; SN : Types.SequenceNumber_T)
   is
      use type Types.SequenceNumber_T;
      Idx : Natural;
   begin
      if P.Status = null then
         return;
      end if;
      if SN < P.First_SN or else SN > P.Last_SN then
         return;
      end if;
      Idx := Natural (SN - P.First_SN);
      --  GAP: the change exists but is irrelevant; treat as received.
      P.Status.all (Idx) := RECEIVED;
   end Irrelevant_Change_Set;

   function Available_Changes_Max (P : WriterProxy)
     return Types.SequenceNumber_T
   is
      use type Types.SequenceNumber_T;
      SN  : Types.SequenceNumber_T;
      Idx : Natural;
      Max : Types.SequenceNumber_T := 0;
   begin
      if P.Status = null then
         return 0;
      end if;
      SN := P.First_SN;
      while SN <= P.Last_SN loop
         Idx := Natural (SN - P.First_SN);
         if P.Status.all (Idx) = RECEIVED or else P.Status.all (Idx) = LOST
         then
            Max := SN;
         end if;
         SN := SN + 1;
      end loop;
      return Max;
   end Available_Changes_Max;

   function Missing_Count (P : WriterProxy) return Natural is
      use type Types.SequenceNumber_T;
      SN    : Types.SequenceNumber_T;
      Idx   : Natural;
      Count : Natural := 0;
   begin
      if P.Status = null then
         return 0;
      end if;
      SN := P.First_SN;
      while SN <= P.Last_SN loop
         Idx := Natural (SN - P.First_SN);
         if P.Status.all (Idx) = MISSING then
            Count := Count + 1;
         end if;
         SN := SN + 1;
      end loop;
      return Count;
   end Missing_Count;

end RTPS.Proto;