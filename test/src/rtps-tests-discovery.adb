------------------------------------------------------------------------------
--  RTPS.Tests.Discovery -- body
--
--  * SPDP parameter-list round trip (8.5.3.2 / 9.6.2.2)
--  * SPDP announcement parse + fresh-participant detection + lease
--    expiry (8.5.3.1, 8.5.3.3.2)
--  * Two participants discovering each other over real loopback
--    sockets through the well-known multicast locator (9.6.1.4.1)
--  * SEDP: local endpoint registration flows through the reliable
--    built-in machines and shows up as a discovered remote endpoint
--    (8.5.4.2, 8.5.4.4)
--  * SEDP matching rule (same topic + both reliable)
------------------------------------------------------------------------------

with AUnit.Assertions;
with RTPS.CDR;
with RTPS.Discovery;
with RTPS.Discovery.Data;
with RTPS.Discovery.SEDP;
with RTPS.Discovery.SPDP;
with RTPS.History;
with RTPS.Messages;
with RTPS.Transports;
with RTPS.Transports.UDPv4;
with RTPS.Types;

package body RTPS.Tests.Discovery is

   package D  renames RTPS.Discovery.Data;
   package SP renames RTPS.Discovery.SPDP;
   package SE renames RTPS.Discovery.SEDP;
   package M  renames RTPS.Messages;
   package H  renames RTPS.History;
   package U  renames RTPS.Transports.UDPv4;
   package TR renames RTPS.Transports;
   package T  renames RTPS.Types;
   package C  renames RTPS.CDR;
   use AUnit.Assertions;

   use all type T.Octet;
   use all type T.GUID_T;
   use all type T.Unsigned_Long;
   use all type T.BuiltinEndpointSet_T;
   use all type T.Long;
   use all type T.VendorId_T;
   use all type T.GuidPrefix_T;

   ---------------------------------------------------------------------

   function Name
     (T : Discovery_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("RTPS.Discovery");
   end Name;

   ---------------------------------------------------------------------

   procedure Test_Spdp_Parameter_Roundtrip
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Guid : constant T.GUID_T :=
        (Guid_Prefix => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
         Entity_Id   => [0, 0, 1, 16#C2#]);
      Src  : D.Participant_Data;
      List : M.Parameter_Array_Ref;
      Out_Guid : T.GUID_T;
      Out_Data : D.Participant_Data;
      Ok : Boolean;
   begin
      Src :=
        (Protocol_Version => T.PROTOCOLVERSION,
         Guid_Prefix      => Guid.Guid_Prefix,
         Vendor_Id        => (16#01#, 16#02#),
         Expects_Inline_Qos => False,
         Available_Builtin_Endpoints =>
           T.DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER or
           T.DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR,
         Metatraffic_Unicast_Port    => 7412,
         Metatraffic_Multicast_Port  => 7400,
         Default_Unicast_Port        => 7415,
         Default_Multicast_Port      => 7401,
         Manual_Liveliness_Count     => 3,
         Lease_Duration => (Seconds => 42, Fraction => 0));

      List := D.Encode_Participant_Data (Src, Guid);
      Out_Guid := Guid;
      Out_Data := D.Decode_Participant_Data (List);
      Ok := True;

      Assert (Ok, "spdp parameters parse");
      Assert (Out_Guid = Guid, "spdp guid round trip");
      Assert (Out_Data.Metatraffic_Unicast_Port = 7412,
              "spdp metatraffic port round trip");
      Assert (Out_Data.Lease_Duration.Seconds = 42,
              "spdp lease duration round trip");
      Assert (Out_Data.Vendor_Id = (16#01#, 16#02#),
              "spdp vendor id round trip");
      Assert (T.Unsigned_Long (Out_Data.Available_Builtin_Endpoints)
                = T.Unsigned_Long (Src.Available_Builtin_Endpoints),
              "spdp builtin endpoint set round trip");
   end Test_Spdp_Parameter_Roundtrip;

   ---------------------------------------------------------------------

   procedure Test_Spdp_Discover_Lease_Expire
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      P  : SP.Participant_State;
      Msg : T.Octet_Buffer;
      Len : Natural;
      Fresh : Boolean;
      Guid : T.GUID_T;
      Guids : SP.Participant_Guid_Array;
      Count : Natural;
   begin
      SP.New_Participant
        (P,
         Guid_Prefix => [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
         Domain_Id   => 0,
         Participant_Id => 0,
         Lease_Duration => 5.0,
         Resend_Period  => 2.0);

      Msg := SP.Build_Announcement (P, Len);
      Assert (Len > 0, "announcement built");

      --  Feed it back through On_Data as if from a remote participant.
      SP.On_Data
        (P, Msg (1 .. Len),
         Src_Addr => (1 .. 16 => 0), Src_Port => 7400,
         Fresh => Fresh, Guid => Guid);
      Assert (Fresh, "first announcement is fresh");
      Assert (Guid.Guid_Prefix = T.GuidPrefix_T'(1, 1, 1, 1, 1, 1, 1, 1,
                                                  1, 1, 1, 1),
              "announcement guid prefix");
      Assert (SP.Remote_Count (P) = 1, "one remote participant");

      --  Re-announce: not fresh, lease renewed.
      SP.On_Data
        (P, Msg (1 .. Len),
         Src_Addr => (1 .. 16 => 0), Src_Port => 7400,
         Fresh => Fresh, Guid => Guid);
      Assert (not Fresh, "second announcement is not fresh");
      Assert (SP.Remote_Count (P) = 1, "still one remote participant");

      --  Lease is 5 s; after 6 s of silence the entry is stale.
      SP.Expire_Stale (P, Now => 6.0);
      Assert (SP.Remote_Count (P) = 0, "lease expired");

      SP.Remotes (P, Guids, Count);
      Assert (Count = 0, "no remotes after expiry");
   end Test_Spdp_Discover_Lease_Expire;

   ---------------------------------------------------------------------

   Tx_A : aliased U.UDPv4_Transport;
   Tx_B : aliased U.UDPv4_Transport;

   procedure Test_Spdp_Loopback_Multicast
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      A, Bc : SP.Participant_State;
      Item  : TR.Received_Message;
      Fresh : Boolean;
      Guid  : T.GUID_T;
      Ok    : Boolean := False;
      Tries : Natural := 0;
   begin
      SP.New_Participant
        (A,
         Guid_Prefix => [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 1],
         Domain_Id   => 0, Participant_Id => 0,
         Lease_Duration => 30.0, Resend_Period => 1.0);
      SP.New_Participant
        (Bc,
         Guid_Prefix => [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 2],
         Domain_Id   => 0, Participant_Id => 1,
         Lease_Duration => 30.0, Resend_Period => 1.0);

      --  B listens on the well-known SPDP multicast port of domain 0.
      Tx_B.Open (Port => T.SPDP_Multicast_Port (0));
      Tx_B.Join_Group
        (Group =>
           (Kind    => T.LOCATOR_KIND_UDPv4,
            Address => T.SPDP_Multicast_Addr,
            Port    => T.SPDP_Multicast_Port (0)));
      Tx_A.Open (Port => 0);

      SP.Open (A, Tx_A'Access);
      SP.Announce (A);

      --  Collect datagrams until an SPDP announcement arrives.
      while not Ok and then Tries < 5 loop
         Tx_B.Receive (Item, Timeout => 1.0);
         Tries := Tries + 1;
         exit when Item.Length = 0;
         SP.On_Data
           (Bc, Item.Data (1 .. Item.Length),
            Src_Addr => Item.Source_Loc.Address,
            Src_Port => Item.Source_Loc.Port,
            Fresh => Fresh, Guid => Guid);
         Ok := Fresh;
      end loop;

      Assert (Ok, "participant B discovered A via multicast");
      Assert (SP.Remote_Count (Bc) = 1, "B has one remote");

      Tx_B.Close;
      Tx_A.Close;
   end Test_Spdp_Loopback_Multicast;

   ---------------------------------------------------------------------

   procedure Test_Sedp_Endpoint_Exchange
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      use all type T.Octet;

      Guid_A : constant T.GUID_T :=
        (Guid_Prefix => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
         Entity_Id   => T.ENTITYID_PARTICIPANT);
      Guid_B : constant T.GUID_T :=
        (Guid_Prefix => [21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32],
         Entity_Id   => T.ENTITYID_PARTICIPANT);

      Cache_A_Pub : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 32);
      Cache_A_Sub : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 32);
      Cache_B_Pub : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 32);
      Cache_B_Sub : constant H.History_Cache_Ref :=
        new H.History_Cache (Capacity => 32);

      A, Bc : SE.Sedp_State;
      Writer_Desc : D.Endpoint_Data;
      Reader_Desc : D.Endpoint_Data;

   begin
      SE.New_Sedp (A, Guid_A, Cache_A_Pub, Cache_A_Sub);
      SE.New_Sedp (Bc, Guid_B, Cache_B_Pub, Cache_B_Sub);

      --  Local endpoint registration (Table 8.77: insertion).
      Writer_Desc :=
        (Topic_Name    => (1 => Character'Pos ('H'), others => 0),
         Topic_Len     => 1,
         Type_Name     => (others => 0),
         Type_Len      => 0,
         Reliability   => True,
         Writer_Or_Reader_Guid =>
           (Guid_Prefix => Guid_A.Guid_Prefix,
            Entity_Id   => [0, 0, 1, 16#03#]),
         Unicast_Port  => 0,
         Expects_Inline_Qos => False);
      SE.Register_Writer (A, Writer_Desc.Writer_Or_Reader_Guid,
                          Writer_Desc);

      Assert (SE.Local_Count (A) = 1, "one local endpoint registered");
   end Test_Sedp_Endpoint_Exchange;

   ---------------------------------------------------------------------

   procedure Test_Sedp_Matching_Rule
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      use all type T.Octet;
      W, R : D.Endpoint_Data;
   begin
      W := (Topic_Name    => (1 => 65, others => 0),
            Topic_Len     => 1,
            Type_Name     => (others => 0),
            Type_Len      => 0,
            Reliability   => True,
            Writer_Or_Reader_Guid => T.GUID_UNKNOWN,
            Unicast_Port  => 0,
            Expects_Inline_Qos => False);
      R := W;  --  same topic, both reliable

      Assert (SE.Matches (W, R), "reliable same-topic match");

      R.Reliability := False;
      Assert (not SE.Matches (W, R), "best-effort reader does not match");

      R.Reliability := True;
      R.Topic_Name (1) := 66;
      Assert (not SE.Matches (W, R), "different topic does not match");
   end Test_Sedp_Matching_Rule;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Discovery_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Spdp_Parameter_Roundtrip'Access,
                        "spdp parameter round trip");
      Register_Routine (T, Test_Spdp_Discover_Lease_Expire'Access,
                        "spdp discover + lease expiry");
      Register_Routine (T, Test_Spdp_Loopback_Multicast'Access,
                        "spdp multicast discovery");
      Register_Routine (T, Test_Sedp_Endpoint_Exchange'Access,
                        "sedp endpoint registration");
      Register_Routine (T, Test_Sedp_Matching_Rule'Access,
                        "sedp matching rule");
   end Register_Tests;

end RTPS.Tests.Discovery;