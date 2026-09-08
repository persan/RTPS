------------------------------------------------------------------------------
--  RTPS.Discovery.SEDP -- Simple Endpoint Discovery Protocol (8.5.4)
--
--  Exchanges DiscoveredWriterData / DiscoveredReaderData between
--  participants over reliable built-in endpoints (SEDPbuiltin-
--  PublicationsWriter/Reader and SEDPbuiltinSubscriptionsWriter/
--  Reader, 8.5.4.2), implemented with the StatefulWriter/StatefulReader
--  protocol machines of 8.4.9.2 / 8.4.12.2.
--
--  The payload of the built-in DATA submessages is a ParameterList
--  (9.6.2.2).  On receiving endpoint data for a remote endpoint, the
--  application callback decides the matching; the Ready_Match helper
--  implements the matching rule for user endpoints (reliable writer
--  with reliable reader on the same topic).
------------------------------------------------------------------------------

with RTPS.Discovery.Data;
with RTPS.History;
with RTPS.StatefulWriter;
with RTPS.StatefulReader;
with RTPS.Transports;
with RTPS.Types;

package RTPS.Discovery.SEDP is

   package T renames RTPS.Types;

   Max_Local_Endpoints  : constant := 64;
   Max_Remote_Endpoints : constant := 64;

   type Endpoint_Kind is (Kind_Writer, Kind_Reader);

   type Local_Endpoint is record
      Guid          : T.GUID_T := T.GUID_UNKNOWN;
      Kind          : Endpoint_Kind := Kind_Writer;
      Topic         : Data.Endpoint_Data;
      --  Cache/machines are owned by the application; discovery only
      --  needs the description.
   end record;

   type Local_Endpoints is
     array (1 .. Max_Local_Endpoints) of Local_Endpoint;

   type Remote_Endpoint is record
      Guid          : T.GUID_T := T.GUID_UNKNOWN;
      Kind          : Endpoint_Kind := Kind_Writer;
      Topic         : Data.Endpoint_Data;
      Participant   : T.GuidPrefix_T := T.GUIDPREFIX_UNKNOWN;
   end record;

   type Remote_Endpoints is
     array (1 .. Max_Remote_Endpoints) of Remote_Endpoint;

   type Sedp_State is limited private;

   ---------------------------------------------------------------------
   --  Setup: the SEDP endpoints themselves (8.5.4.2/8.5.4.3)
   ---------------------------------------------------------------------

   procedure New_Sedp
     (Self            : in out Sedp_State;
      Participant_Guid :       T.GUID_T;
      Publications_Cache :     RTPS.History.History_Cache_Ref;
      Subscriptions_Cache :    RTPS.History.History_Cache_Ref);
   --  Creates SEDPbuiltinPublicationsWriter/Reader (reliable, on the
   --  publications cache) and SEDPbuiltinSubscriptionsWriter/Reader
   --  (reliable, on the subscriptions cache).

   procedure Open
     (Self : in out Sedp_State; To : RTPS.Transports.Transport_Ref);

   ---------------------------------------------------------------------
   --  Matching against a discovered participant (8.5.5.1)
   ---------------------------------------------------------------------

   procedure Match_Participant
     (Self          : in out Sedp_State;
      Participant    :        T.GUID_T;
      Meta_Port      :        T.Unsigned_Long;
      Expects_Inline  :        Boolean := False);
   --  8.5.5.1: after the SPDP discovered a participant, match the four
   --  SEDP machines with the remote built-in endpoints (guid =
   --  <participant.guidPrefix, ENTITYID_SEDP_BUILTIN_*>) so the
   --  endpoint data starts flowing.

   procedure Unmatch_Participant
     (Self : in out Sedp_State; Participant : T.GUID_T);
   --  8.5.5.2: remove the proxies for the remote built-in endpoints.

   ---------------------------------------------------------------------
   --  Local endpoint registration (Table 8.77/8.78: insertion)
   ---------------------------------------------------------------------

   procedure Register_Writer
     (Self  : in out Sedp_State;
      Guid  :        T.GUID_T;
      Desc  :        Data.Endpoint_Data);
   --  Data-object insertion in the publications HistoryCache: a DATA
   --  (ALIVE) change with the DiscoveredWriterData parameter list.

   procedure Register_Reader
     (Self  : in out Sedp_State;
      Guid  :        T.GUID_T;
      Desc  :        Data.Endpoint_Data);

   ---------------------------------------------------------------------
   --  Wire driving (the application pumps these)
   ---------------------------------------------------------------------

   procedure Send_Heartbeats (Self : in out Sedp_State);
   --  T7 on both SEDP writers.

   procedure Push_Pending (Self : in out Sedp_State);
   --  T4/T12: push unsent endpoint data to all matched readers.

   --  Deliver a received built-in DATA to the SEDP reader machines.
   --  Handled is True when the submessage belonged to a SEDP endpoint.
   procedure On_Data
     (Self     : in out Sedp_State;
      Writer_Id :       T.EntityId_T;
      SN       :        T.SequenceNumber_T;
      Payload  :        T.Octet_Buffer;
      Payload_Length : Natural;
      Handled  :    out Boolean);

   --  Deliver a received built-in HEARTBEAT / ACKNACK to the SEDP
   --  machines; Ack_Request is True when an ACKNACK must be sent.
   procedure On_Heartbeat
     (Self     : in out Sedp_State;
      Writer_Id :       T.EntityId_T;
      First_SN :        T.SequenceNumber_T;
      Last_SN  :        T.SequenceNumber_T;
      Final    :        Boolean;
      Ack_Request :  out Boolean);

   procedure On_Acknack
     (Self     : in out Sedp_State;
      Reader_Id :       T.EntityId_T;
      Writer_Id :       T.EntityId_T;
      Base_SN  :        T.SequenceNumber_T;
      Bitmap   :        T.Unsigned_Long;
      Num_Bits :        T.Unsigned_Long;
      Final    :        Boolean;
      Repair   :    out Boolean);

   ---------------------------------------------------------------------
   --  Discovery results
   ---------------------------------------------------------------------

   function Remote_Count (Self : Sedp_State) return Natural;

   procedure Remotes
     (Self  : Sedp_State;
      List  :    out Remote_Endpoints;
      Count :    out Natural);

   --  Registered local endpoints (for the test and for echoing).
   function Local_Count (Self : Sedp_State) return Natural;

   ---------------------------------------------------------------------
   --  Matching rule helper
   ---------------------------------------------------------------------

   function Matches
     (Writer_Desc : Data.Endpoint_Data;
      Reader_Desc : Data.Endpoint_Data) return Boolean;
   --  True when the two endpoints should be matched: same topic name
   --  and both reliable (8.5.4.2: SEDP endpoints are reliable; user
   --  endpoints follow their own QoS).

private

   type Sedp_State is record
      Participant_Guid : T.GUID_T := T.GUID_UNKNOWN;

      --  Built-in SEDP endpoints (reliable):
      Pub_Writer  : RTPS.StatefulWriter.Writer_State;
      Pub_Reader  : RTPS.StatefulReader.Reader_State;
      Sub_Writer  : RTPS.StatefulWriter.Writer_State;
      Sub_Reader  : RTPS.StatefulReader.Reader_State;
      Pub_Cache   : RTPS.History.History_Cache_Ref := null;
      Sub_Cache   : RTPS.History.History_Cache_Ref := null;

      Locals      : Local_Endpoints;
      Local_Count : Natural := 0;
      Remote_List : Remote_Endpoints;
      Remote_Num  : Natural := 0;
   end record;

end RTPS.Discovery.SEDP;