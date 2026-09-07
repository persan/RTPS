------------------------------------------------------------------------------
--  RTPS.Receiver -- body: message parse + receiver state machine
--
--  Implements the Rules for the Message Receiver (8.3.4.1):
--    1. If message length < 20 octets, the Header is invalid -> drop.
--    2. Check 'R''T''P''S' magic; parse version, vendorId, guidPrefix
--       into the receiver state.
--    3. Reject major version > supported (2).
--    4. Parse each Submessage in turn; apply the interpretation rules
--       for the Info submessages to the state (InfoTS/InfoSrc/InfoDst
--       set the current timestamp/source/destination), and deliver every
--       submessage to the Sink.
------------------------------------------------------------------------------

package body RTPS.Receiver is

   procedure Process_Message
     (Data   :        RTPS.Types.Octet_Array;
      S      : in out Receiver_State;
      Target : in out Sink'Class)
   is
      use type RTPS.Types.Octet;
      Buf  : RTPS.Types.Octet_Buffer := new RTPS.Types.Octet_Array'(Data);
      Strm : CDR.Stream;
   begin
      --  Rule 1: Header validity (8.3.6.3).
      if Data'Length < Messages.Header_Length then
         return;  --  invalid header: silently ignore message
      end if;

      CDR.Bind (Strm, CDR.Octet_Array_Access (Buf), Data'Length);

      declare
         H : Messages.Header_T;
      begin
         begin
            Messages.Decode_Header (Strm, H);
         exception
            when Constraint_Error =>
               --  Invalid magic (8.3.6.3): the Header is invalid and the
               --  message is silently ignored.
               return;
         end;

         --  Rule 3: version check.
         if H.Version.Major > RTPS.Types.PROTOCOLVERSION.Major then
            return;
         end if;

         S.Source_Version     := H.Version;
         S.Source_Vendor_Id   := H.Vendor_Id;
         S.Source_Guid_Prefix := H.Guid_Prefix;
         S.Have_Source_Info   := True;
      end;

      --  Rule 4: parse and dispatch each submessage.
      while Strm.Last < Strm.Limit
      loop
         declare
            SM : Messages.Submessage_T;
         begin
            Messages.Decode_Submessage (Strm, SM);

            --  Update interpreter state per 8.3.4.1 step 3.
            case SM.Kind is
               when Messages.KIND_INFO_TS =>
                  S.Have_Timestamp := not SM.Invalidate;
                  S.Timestamp := SM.Timestamp;
               when Messages.KIND_INFO_SRC =>
                  S.Source_Version     := SM.Version;
                  S.Source_Vendor_Id   := SM.Vendor_Id;
                  S.Source_Guid_Prefix := SM.Src_Guid_Prefix;
                  S.Have_Timestamp := False;
               when Messages.KIND_INFO_DST =>
                  S.Dest_Guid_Prefix := SM.Dst_Guid_Prefix;
               when Messages.KIND_INFO_REPLY =>
                  null;  --  reply locators handled by callback consumers
               when others =>
                  null;
            end case;

            --  Deliver to the application sink.
            On_Submessage (Target, SM);
         end;
      end loop;
   end Process_Message;

end RTPS.Receiver;