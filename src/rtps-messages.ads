------------------------------------------------------------------------------
--  RTPS.Messages
--
--  The RTPS Messages Module (clause 8.3) and its UDP PSM wire mapping
--  (clauses 9.4.4, 9.4.5).
--
--  Every message is a Header followed by Submessages.  Each Submessage
--  is a SubmessageHeader (submessageKind, flags, octetsToNextHeader)
--  followed by SubmessageElements.
--
--  Serialization is explicit and endianness-controlled per submessage
--  (EndiannessFlag E).  All numeric fields use little- or big-endian CDR
--  mapping per 9.2.3.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.CDR;

package RTPS.Messages is

   use type RTPS.Types.Octet;

   ---------------------------------------------------------------------
   --  Header (8.3.3.1 / 9.4.4)
   ---------------------------------------------------------------------

   --  Wire layout (20 octets):
   --    'R' 'T' 'P' 'S' | version.major version.minor | vendorId[2] |
   --    guidPrefix[12]
   Header_Length : constant := 20;

   PROTOCOL_RTPS : constant RTPS.Types.Octet_Array (1 .. 4) :=
     (16#52#, 16#54#, 16#50#, 16#53#);  --  "RTPS"

   type Header_T is record
      Version    : RTPS.Types.ProtocolVersion_T := RTPS.Types.PROTOCOLVERSION;
      Vendor_Id  : RTPS.Types.VendorId_T        :=
        RTPS.Types.VENDORID_UNKNOWN;
      Guid_Prefix: RTPS.Types.GuidPrefix_T      :=
        RTPS.Types.GUIDPREFIX_UNKNOWN;
   end record;

   procedure Encode_Header
     (S : in out CDR.Stream'Class; H : Header_T);
   procedure Decode_Header
     (S : in out CDR.Stream'Class; H : out Header_T);

   ---------------------------------------------------------------------
   --  SubmessageKind (9.4.5.1.1)
   ---------------------------------------------------------------------

   type Submessage_Kind is
     (KIND_PAD,             --  0x01
      KIND_ACKNACK,         --  0x06
      KIND_HEARTBEAT,       --  0x07
      KIND_GAP,             --  0x08
      KIND_INFO_TS,         --  0x09
      KIND_INFO_SRC,        --  0x0c
      KIND_INFO_REPLY_IP4,  --  0x0d (PSM specific)
      KIND_INFO_DST,        --  0x0e
      KIND_INFO_REPLY,      --  0x0f
      KIND_NACK_FRAG,       --  0x12
      KIND_HEARTBEAT_FRAG,  --  0x13
      KIND_DATA,            --  0x15
      KIND_DATA_FRAG);      --  0x16

   Kind_Code : constant array (Submessage_Kind) of RTPS.Types.Octet :=
     (KIND_PAD            => 16#01#,
      KIND_ACKNACK        => 16#06#,
      KIND_HEARTBEAT      => 16#07#,
      KIND_GAP            => 16#08#,
      KIND_INFO_TS        => 16#09#,
      KIND_INFO_SRC       => 16#0C#,
      KIND_INFO_REPLY_IP4 => 16#0D#,
      KIND_INFO_DST       => 16#0E#,
      KIND_INFO_REPLY     => 16#0F#,
      KIND_NACK_FRAG      => 16#12#,
      KIND_HEARTBEAT_FRAG => 16#13#,
      KIND_DATA           => 16#15#,
      KIND_DATA_FRAG      => 16#16#);

   ---------------------------------------------------------------------
   --  Submessage flags (9.4.5.1.2).  Bit positions per submessage kind.
   ---------------------------------------------------------------------

   FLAG_E : constant := 2#0000_0001#;   --  EndiannessFlag (all)
   FLAG_F : constant := 2#0000_0010#;   --  FinalFlag (AckNack, HB)
   FLAG_Q : constant := 2#0000_0010#;   --  InlineQosFlag (Data, DataFrag)
   FLAG_L : constant := 2#0000_0100#;   --  LivelinessFlag (HB)
   FLAG_D : constant := 2#0000_0100#;   --  DataFlag (Data)
   FLAG_K : constant := 2#0000_1000#;   --  KeyFlag (Data); (DataFrag: 0x04)
   FLAG_M : constant := 2#0000_0010#;   --  MulticastFlag (InfoReply, IP4)
   FLAG_I : constant := 2#0000_0010#;   --  InvalidateFlag (InfoTS)

   ---------------------------------------------------------------------
   --  Submessage elements (8.3.5)
   ---------------------------------------------------------------------

   type SequenceNumberSet_T is record
      Bitmap_Base : RTPS.Types.SequenceNumber_T := 1;
      Num_Bits    : RTPS.Types.Unsigned_Long := 0;   --  0 < numBits <= 256
      Bitmap      : RTPS.Types.Unsigned_Long := 0;   --  up to 256 bits
   end record;
   --  Valid sets span an interval of at most 256 sequence numbers, so
   --  the bitmap fits in 8 longs on the wire; we model it as a single
   --  256-bit bitmap (two longs max used: bits 0..255).
   --  seqNum in set  <=>  Bitmap_Base <= seqNum < Bitmap_Base + Num_Bits
   --                     and Bitmap (deltaN / 32) & (1 << (31 - deltaN % 32))

   type FragmentNumberSet_T is record
      Bitmap_Base : RTPS.Types.FragmentNumber_T := 1;
      Num_Bits    : RTPS.Types.Unsigned_Long := 0;
      Bitmap      : RTPS.Types.Unsigned_Long := 0;
   end record;

   type Parameter_T is record
      Parameter_Id : RTPS.Types.ParameterId_T := 0;
      Length       : RTPS.Types.Unsigned_Short := 0;
      Value        : RTPS.Types.Octet_Buffer := null;
      --  Value octets (Length of them); caller retains ownership.
   end record;

   type Parameter_Array is array (Natural range <>) of Parameter_T;
   type Parameter_Array_Ref is access Parameter_Array;

   ---------------------------------------------------------------------
   --  Submessage record (8.3.7).  A single record covers all kinds;
   --  fields not meaningful for a given kind are ignored.  Common wire
   --  components (readerId, writerId, count, writerSN) are shared
   --  because they occupy the same logical role in every submessage
   --  that carries them.
   ---------------------------------------------------------------------

   type Submessage_T (Kind : Submessage_Kind := KIND_PAD) is record
      Endianness : CDR.Endianness := CDR.Little_Endian;

      --  Endpoint ids: present in ACKNACK, HEARTBEAT, GAP, NACK_FRAG,
      --  HEARTBEAT_FRAG, DATA, DATA_FRAG.
      Reader_Id : RTPS.Types.EntityId_T := RTPS.Types.ENTITYID_UNKNOWN;
      Writer_Id : RTPS.Types.EntityId_T := RTPS.Types.ENTITYID_UNKNOWN;

      --  Writer sequence number: DATA, DATA_FRAG, NACK_FRAG,
      --  HEARTBEAT_FRAG.
      Writer_SN : RTPS.Types.SequenceNumber_T := 1;

      --  Duplicate-detection count: ACKNACK, HEARTBEAT, NACK_FRAG,
      --  HEARTBEAT_FRAG.
      Count : RTPS.Types.Count_T := 0;

      --  Kind-specific flag booleans.
      Final      : Boolean := False;  --  ACKNACK.F, HEARTBEAT.F
      Liveliness : Boolean := False;  --  HEARTBEAT.L
      Invalidate : Boolean := False;  --  INFO_TS.I
      Has_Multicast : Boolean := False; --  INFO_REPLY.M, INFO_REPLY_IP4.M

      case Kind is
         when KIND_PAD =>
            null;

         when KIND_ACKNACK =>
            Reader_SN_State : SequenceNumberSet_T;

         when KIND_HEARTBEAT =>
            First_SN  : RTPS.Types.SequenceNumber_T := 1;
            Last_SN   : RTPS.Types.SequenceNumber_T := 0;

         when KIND_GAP =>
            Gap_Start : RTPS.Types.SequenceNumber_T := 1;
            Gap_List  : SequenceNumberSet_T;

         when KIND_INFO_TS =>
            Timestamp : RTPS.Types.Time_T := RTPS.Types.TIME_ZERO;

         when KIND_INFO_SRC =>
            Unused    : RTPS.Types.Unsigned_Long := 0;
            Version   : RTPS.Types.ProtocolVersion_T :=
              RTPS.Types.PROTOCOLVERSION;
            Vendor_Id : RTPS.Types.VendorId_T := RTPS.Types.VENDORID_UNKNOWN;
            Src_Guid_Prefix : RTPS.Types.GuidPrefix_T :=
              RTPS.Types.GUIDPREFIX_UNKNOWN;

         when KIND_INFO_REPLY_IP4 =>
            Unicast   : RTPS.Types.Locator_T;
            Multicast : RTPS.Types.Locator_T;

         when KIND_INFO_DST =>
            Dst_Guid_Prefix : RTPS.Types.GuidPrefix_T :=
              RTPS.Types.GUIDPREFIX_UNKNOWN;

         when KIND_INFO_REPLY =>
            Unicast_List   : RTPS.Types.Locator_Buffer := null;
            Multicast_List : RTPS.Types.Locator_Buffer := null;

         when KIND_NACK_FRAG =>
            Fragment_Number_State : FragmentNumberSet_T;

         when KIND_HEARTBEAT_FRAG =>
            Last_Fragment_Num : RTPS.Types.FragmentNumber_T := 1;

         when KIND_DATA | KIND_DATA_FRAG =>
            Extra_Flags : RTPS.Types.Unsigned_Short := 0;
            Octets_To_Inline_Qos : RTPS.Types.Unsigned_Short := 0;
            --  Data submessage only:
            Inline_Qos : Parameter_Array_Ref := null;  --  present if Q=1
            Has_Payload : Boolean := False;            --  D=1 or K=1
            Is_Key      : Boolean := False;            --  K=1 (Data)
            --  DataFrag submessage only:
            Fragment_Starting_Num : RTPS.Types.FragmentNumber_T := 1;
            Fragments_In_Submessage : RTPS.Types.Unsigned_Short := 0;
            Fragment_Size : RTPS.Types.Unsigned_Short := 0;
            Sample_Size   : RTPS.Types.Unsigned_Long := 0;
            Payload : RTPS.Types.Octet_Buffer := null; --  serialized payload
            Payload_Length : Natural := 0;
      end case;
   end record;

   type Submessage_Array is array (Positive range <>) of Submessage_T;
   type Submessage_Array_Ref is access Submessage_Array;

   ---------------------------------------------------------------------
   --  Wire encoding / decoding (9.4.5)
   ---------------------------------------------------------------------

   procedure Encode_Submessage
     (S   : in out CDR.Stream'Class;
      SM  : Submessage_T;
      Last_Submessage : Boolean := True);
   --  Serialize one Submessage.  When Last_Submessage is True the
   --  octetsToNextHeader field is set to 0 (meaning "extends to end of
   --  message"), except for PAD and INFO_TS where 0 means "next header
   --  immediately follows" (9.4.5.1.3).

   procedure Decode_Submessage
     (S   : in out CDR.Stream'Class;
      SM  : out Submessage_T);
   --  Parse one Submessage from the stream.  Raises Constraint_Error on
   --  malformed input.

   function Decode_Kind (Code : RTPS.Types.Octet) return Submessage_Kind with
     Pre => Code in 16#01# | 16#06# | 16#07# | 16#08# | 16#09# | 16#0C# |
                     16#0D# | 16#0E# | 16#0F# | 16#12# | 16#13# | 16#15# |
                     16#16#;

   Unknown_Kind : exception;

end RTPS.Messages;