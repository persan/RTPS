------------------------------------------------------------------------------
--  RTPS.Tests.Support -- body
------------------------------------------------------------------------------

package body RTPS.Tests.Support is

   function Encode_Message
     (Hdr : Messages.Header_T;
      SMs : Messages.Submessage_Array_Ref;
      Len : Natural := RTPS.Max_Message_Size) return Types.Octet_Buffer
   is
      S : CDR.Stream;
   begin
      declare
         Result : CDR.Octet_Array_Access := new Types.Octet_Array (1 .. Len);
      begin
         CDR.Bind (S, Result, Len);
         Messages.Encode_Header (S, Hdr);
         for K in SMs'Range loop
            Messages.Encode_Submessage (S, SMs (K), Last_Submessage => True);
         end loop;
         Enc_Len := S.Last;
         return Types.Octet_Buffer (Result);
      end;
   end Encode_Message;

end RTPS.Tests.Support;