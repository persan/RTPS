------------------------------------------------------------------------------
--  RTPS.Tests.Liveliness -- body
--
--  * ParticipantMessageData encode/decode round trip (9.6.2.1)
--  * Writer liveliness assertion -> reliable delivery over the real
--    protocol machines -> lease renewal on the reader side (8.4.13.5)
--  * Lease expiry bookkeeping (Set_Lease / Lease_Expired)
--  * SPDP manualLivelinessCount bump forces an immediate announcement
--    (Table 8.73)
------------------------------------------------------------------------------

with AUnit.Assertions;
with RTPS.CDR;
with RTPS.Discovery.SPDP;
with RTPS.History;
with RTPS.Liveliness;
with RTPS.Messages;
with RTPS.StatefulReader;
with RTPS.StatefulWriter;
with RTPS.Transports.UDPv4;
with RTPS.Types;

package body RTPS.Tests.Liveliness is

   package L  renames RTPS.Liveliness;
   package SP renames RTPS.Discovery.SPDP;
   package H  renames RTPS.History;
   package M  renames RTPS.Messages;
   package SW renames RTPS.StatefulWriter;
   package SR renames RTPS.StatefulReader;
   package U  renames RTPS.Transports.UDPv4;
   package T  renames RTPS.Types;
   use AUnit.Assertions;

   Tx_Live : aliased U.UDPv4_Transport;
   Tx_Spdp : aliased U.UDPv4_Transport;

   use all type T.Octet;
   use all type T.GUID_T;
   use all type T.GuidPrefix_T;
   use all type T.Count_T;
   use all type T.Octet_Array;
   use type T.Octet_Buffer;
   use all type L.Message_Kind;
   use type H.Cache_Change_Ref;

   ---------------------------------------------------------------------

   function Name (T : Liveliness_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("RTPS.Liveliness");
   end Name;

   ---------------------------------------------------------------------

   procedure Test_Message_Data_Roundtrip
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Part : constant T.GuidPrefix_T :=
        (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
      Kind : constant L.Message_Kind := L.PMDK_MANUAL_LIVELINESS_UPDATE;
      Data : constant T.Octet_Array (1 .. 6) := (16#A0#, 16#B1#, 16#C2#,
                                                 16#D3#, 16#E4#, 16#F5#);
      Wire : T.Octet_Buffer;
      Out_Part : T.GuidPrefix_T;
      Out_Kind : L.Message_Kind;
      Out_Data : T.Octet_Buffer;
      Out_Len  : Natural;
      Ok    : Boolean;
   begin
      Wire := L.Encode (Part, Kind, Data);
      L.Decode (Wire.all, Out_Part, Out_Kind, Out_Data, Out_Len, Ok);

      Assert (Ok, "participant message data decodes");
      Assert (Out_Part = Part, "participant guid prefix round trip");
      Assert (Out_Kind = Kind, "kind round trip");
      Assert (Out_Len = 6, "data length round trip");
      Assert (Out_Data /= null and then Out_Data.all = Data,
              "data octets round trip");

      --  9.6.2.1: minimum 20 octets; malformed short input rejected.
      declare
         Short : constant T.Octet_Array (1 .. 10) := (others => 0);
         Ok2   : Boolean;
         P2 : T.GuidPrefix_T; K2 : L.Message_Kind;
         D2 : T.Octet_Buffer; N2 : Natural;
      begin
         L.Decode (Short, P2, K2, D2, N2, Ok2);
         Assert (not Ok2, "short input rejected");
      end;
   end Test_Message_Data_Roundtrip;

   ---------------------------------------------------------------------

   procedure Test_Assert_Renews_Lease
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Part_A : constant T.GuidPrefix_T :=
        (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1);
      Part_B : constant T.GuidPrefix_T :=
        (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2);

      Cache_W : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 16);
      Cache_R : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 16);

      W : L.Writer;
      R : L.Reader;

      Writer_Guid : constant T.GUID_T :=
        (Guid_Prefix => Part_A,
         Entity_Id   => T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER);

      Handled : Boolean;
      Ack : Boolean;
      Acknack : M.Submessage_T;
      Ok : Boolean;
   begin
      L.New_Writer (W, Part_A, Cache_W);
      L.New_Reader (R, Part_B, Cache_R);

      --  Match the built-in endpoints (8.4.13.1).
      L.Matched_Writer_Add
        (R, (Guid_Prefix => Part_A,
             Entity_Id   => T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER));
      L.Matched_Reader_Add
        (W, (Guid_Prefix => Part_B,
             Entity_Id   => T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER),
         Meta_Port => 7415);

      Tx_Live.Open (Port => 0);
      L.Open (W, Tx_Live'Access);
      L.Set_Now (R, Now => 1.0);

      L.Set_Lease (R, L.Liveliness_Automatic, Lease => 5.0);

      --  Nothing received yet: no lease bookkeeping.
      Assert (not L.Lease_Expired (R, L.Liveliness_Automatic, Now => 0.0),
              "no expiry without assertion");

      --  Writer asserts AUTOMATIC liveliness; the reader receives the
      --  DATA (reliable path through the protocol machines).
      L.Assert (W, L.Liveliness_Automatic);
      declare
         Change : constant H.Cache_Change_Ref := Cache_W.Find (1);
      begin
         Assert (Change /= null, "assertion written to cache");
         L.On_Data
           (R,
            Writer_Id =>
              T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER,
            SN => 1,
            Payload => Change.all.Data,
            Payload_Length => Change.all.Data_Length,
            Handled => Handled);
      end;
      Assert (Handled, "liveliness DATA handled by built-in reader");
      Assert (L.Last_Assertion (R, L.Liveliness_Automatic) > 0.0,
              "assertion time recorded");
      Assert (not L.Lease_Expired
                (R, L.Liveliness_Automatic, Now => 4.0),
              "lease renewed by assertion");

      --  HEARTBEAT from the writer: the reader answers with ACKNACK.
      L.Send_Heartbeat (W);
      L.On_Heartbeat
        (R,
         Writer_Id =>
           T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER,
         First_SN => 1, Last_SN => 1,
         Final => False, Ack_Request => Ack);
      Assert (Ack, "HEARTBEAT Final=False demands ACKNACK");
      L.Make_Acknack
        (R, T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER,
         Acknack, Ok);
      Assert (Ok, "ACKNACK built");
      L.On_Acknack
        (W, Reader_Id =>
              T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER,
         Base_SN => 2, Bitmap => 0, Num_Bits => 0,
         Final => True, Repair => Ok);
      Assert (not Ok, "fully-acked ACKNACK triggers no repair");
   end Test_Assert_Renews_Lease;

   ---------------------------------------------------------------------

   procedure Test_Lease_Expiry
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Part_B : constant T.GuidPrefix_T :=
        (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2);
      Cache_R : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 16);
      R : L.Reader;
      Handled : Boolean;
      Wire : T.Octet_Buffer;
   begin
      L.New_Reader (R, Part_B, Cache_R);
      L.Set_Lease (R, L.Liveliness_Manual_By_Participant, Lease => 2.0);
      L.Set_Now (R, Now => 1.0);

      --  Match the remote built-in writer first: without it the
      --  reader machine drops the DATA silently.
      L.Matched_Writer_Add
        (R, (Guid_Prefix => (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
             Entity_Id   => T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER));

      --  Simulate a received manual-liveliness assertion at t = 1.0.
      Wire := L.Encode
        ((1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
         L.PMDK_MANUAL_LIVELINESS_UPDATE,
         (1 .. 0 => 0));
      L.On_Data
        (R,
         Writer_Id =>
           T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER,
         SN => 1,
         Payload => Wire,
         Payload_Length => Wire.all'Length,
         Handled => Handled);
      Assert (Handled, "manual liveliness DATA handled");

      --  Lease 2.0 from t = 1.0: alive at 3.0, expired at 3.5.
      Assert (not L.Lease_Expired
                (R, L.Liveliness_Manual_By_Participant, Now => 3.0),
              "alive within lease");
      Assert (L.Lease_Expired
                (R, L.Liveliness_Manual_By_Participant, Now => 3.5),
              "expired after lease");
   end Test_Lease_Expiry;

   ---------------------------------------------------------------------

   procedure Test_Manual_Count
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      P : SP.Participant_State;
      Needs : Boolean;
   begin
      SP.New_Participant
        (P,
         Guid_Prefix => [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
         Domain_Id   => 0, Participant_Id => 0,
         Lease_Duration => 100.0, Resend_Period => 30.0);

      --  First announce is always due.
      Needs := SP.Needs_Announce (P, Now => 0.0);
      Assert (Needs, "first announcement due");
      SP.Announce (P);   --  no transport: only timestamps
      SP.Expire_Stale (P, Now => 1.0);  --  advance the clock

      --  Within the resend period nothing is due (the transport-less
      --  announce records the timestamp only when a transport is
      --  attached; give it one).
      Tx_Spdp.Open (Port => 0);
      SP.Open (P, Tx_Spdp'Access);
      SP.Announce (P);
      Tx_Spdp.Close;
      Needs := SP.Needs_Announce (P, Now => 1.0);
      Assert (not Needs, "no announce within resend period");

      --  ... unless manual liveliness was asserted.
      SP.Bump_Manual_Count (P);
      Needs := SP.Needs_Announce (P, Now => 1.0);
      Assert (Needs, "bumped manual count forces announcement");
      Assert (SP.Manual_Count (P) = 1, "manual count incremented");
   end Test_Manual_Count;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Liveliness_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Message_Data_Roundtrip'Access,
                        "participant message data round trip");
      Register_Routine (T, Test_Assert_Renews_Lease'Access,
                        "assert renews lease + reliable exchange");
      Register_Routine (T, Test_Lease_Expiry'Access,
                        "lease expiry");
      Register_Routine (T, Test_Manual_Count'Access,
                        "spdp manual liveliness count");
   end Register_Tests;

end RTPS.Tests.Liveliness;