------------------------------------------------------------------------------
--  RTPS root package -- shared configuration constants (clause 8.2.1.3)
--
--  Protocol timing/tuning defaults.  Types live in RTPS.Types, the
--  message codecs in RTPS.Messages, entities in RTPS.Entities, the
--  receiver in RTPS.Receiver, the history cache in RTPS.History.
------------------------------------------------------------------------------

package RTPS is

   Default_Resend_Period_Sec : constant := 3;
   --  HB period for reliable writers (reference impl ~3s; the SPDP
   --  announcement period of 30s is RTPS.Types.SPDP_RESEND_PERIOD).

   Default_Heartbeat_Period_Sec : constant := 1;

   Max_Message_Size : constant := 65_507;
   --  Classic UDP datagram payload bound; messages are never larger.

   subtype Domain_Id is Natural range 0 .. 232;
   subtype Participant_Id is Natural range 0 .. 119;

end RTPS;