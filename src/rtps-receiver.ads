------------------------------------------------------------------------------
--  RTPS.Receiver
--
--  8.3.4 The RTPS Message Receiver.  Parses a received Message into its
--  Header and Submessages and applies the Rules for the Message Receiver
--  (8.3.4.1), maintaining the interpreter state (sourceVersion,
--  sourceVendorId, sourceGuidPrefix, ...).
--
--  Delivering the parsed submessages to matched readers/writers is the
--  caller's job: a callback receives each submessage in protocol order.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.CDR;
with RTPS.Messages;

package RTPS.Receiver is

   --  Interpreter state of the receiver (8.3.4.1 step 2).
   type Receiver_State is record
      Source_Version      : RTPS.Types.ProtocolVersion_T :=
        RTPS.Types.PROTOCOLVERSION_2_2;
      Source_Vendor_Id    : RTPS.Types.VendorId_T :=
        RTPS.Types.VENDORID_UNKNOWN;
      Source_Guid_Prefix  : RTPS.Types.GuidPrefix_T :=
        RTPS.Types.GUIDPREFIX_UNKNOWN;
      Dest_Guid_Prefix    : RTPS.Types.GuidPrefix_T :=
        RTPS.Types.GUIDPREFIX_UNKNOWN;
      --  Validity checks use these; unicast/multicast reply locators and
      --  timestamps are passed to the callback.
      Have_Timestamp      : Boolean := False;
      Timestamp           : RTPS.Types.Time_T := RTPS.Types.TIME_ZERO;
      Have_Source_Info    : Boolean := False;
   end record;

   type Submessage_Access is access all Messages.Submessage_T;

   type Sink is limited interface;
   --  Consumer of parsed submessages.

   procedure On_Submessage
     (Self : in out Sink;
      SM   : Messages.Submessage_T) is abstract;

   type Sink_Ref is access all Sink'Class;

   Unrecognized_Vendor : exception;

   procedure Process_Message
     (Data   :        RTPS.Types.Octet_Array;
      S      : in out Receiver_State;
      Target : in out Sink'Class);
   --  Parse one complete RTPS Message and dispatch each submessage to
   --  Target in order.  Raises Constraint_Error if the header is
   --  invalid (8.3.6.3): wrong magic, unsupported major version.

end RTPS.Receiver;