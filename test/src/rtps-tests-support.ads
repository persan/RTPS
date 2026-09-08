------------------------------------------------------------------------------
--  RTPS.Tests.Support -- shared helpers for the AUnit test suites.
--
--  Compact message encoder used by several suites; wraps a full RTPS
--  message (Header + submessages) and records the encoded length.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.CDR;
with RTPS.Messages;

package RTPS.Tests.Support is

   Enc_Len : Natural := 0;
   --  Length of the most recently encoded message (transport-visible
   --  message size).

   --  Encode Header + submessages into a fresh buffer.
   function Encode_Message
     (Hdr : Messages.Header_T;
      SMs : Messages.Submessage_Array_Ref;
      Len : Natural := RTPS.Max_Message_Size) return Types.Octet_Buffer;

end RTPS.Tests.Support;