------------------------------------------------------------------------------
--  RTPS.Tests.UDPv4 -- body
--
--  Real-socket integration test: two transports on 127.0.0.1, one
--  sends, the other receives; payload and source locator checked.
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with AUnit.Test_Cases;
with RTPS.Types;
with RTPS.Transports.UDPv4;

package body RTPS.Tests.UDPv4 is

   package T  renames RTPS.Types;
   package U  renames RTPS.Transports.UDPv4;
   use all type T.Octet;
   use all type T.Octet_Buffer;
   use all type T.Long;
   use all type T.Unsigned_Long;

   ---------------------------------------------------------------------

   procedure Test_Send_Receive (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      use all type T.Octet;
      Tx : U.UDPv4_Transport;
      Rx : U.UDPv4_Transport;
      Msg : constant T.Octet_Array (1 .. 12) :=
        [16#52#, 16#54#, 16#50#, 16#53#,  --  "RTPS"
         2, 2, 0, 0, 0, 0, 0, 0];
      Item : RTPS.Transports.Received_Message;
      Dest : Types.Locator_T;
   begin
      --  Bind receiver on an ephemeral port, sender on any port.
      U.UDPv4_Transport'Class (Rx).Open (Port => 0, Reuse_Addr => True);
      U.UDPv4_Transport'Class (Tx).Open (Port => 0, Reuse_Addr => True);

      Dest := Types.Make_UDPv4_Locator
        (127, 0, 0, 1, Rx.Local_Port);

      Tx.Send (Dest, Msg);

      --  Blocking receive: the datagram is already in the queue.
      Rx.Receive (Item, Timeout => 2.0);

      Assert (Item.Length = Msg'Length, "udpv4 datagram length");
      Assert (Item.Data /= null, "udpv4 datagram buffer allocated");
      if Item.Data /= null then
         Assert
           (Item.Data.all (1) = 16#52# and Item.Data.all (4) = 16#53#
            and Item.Data.all (5) = 2,
            "udpv4 datagram payload");
      end if;
      Assert (Item.Source_Loc.Kind = Types.LOCATOR_KIND_UDPv4,
              "udpv4 source locator kind");
      Assert (Item.Source_Loc.Address (13) = 127,
              "udpv4 source address is 127.x.x.x");
      Assert (Item.Source_Loc.Port = Tx.Local_Port,
              "udpv4 source port matches sender");

      Rx.Close;
      Tx.Close;
   end Test_Send_Receive;

   ---------------------------------------------------------------------

   procedure Test_Receive_Timeout
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Rx : U.UDPv4_Transport;
      Item : RTPS.Transports.Received_Message;
   begin
      Rx.Open (Port => 0, Reuse_Addr => True);

      --  Nothing was ever sent to this port; expect a timeout.
      Rx.Receive (Item, Timeout => 0.2);

      Assert (Item.Length = 0, "udpv4 timeout yields empty message");
      Assert (Item.Data = null, "udpv4 timeout yields null buffer");
      Assert (Item.Source_Loc.Kind = Types.LOCATOR_KIND_INVALID,
              "udpv4 timeout yields invalid source");

      Rx.Close;
   end Test_Receive_Timeout;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out UDPv4_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Send_Receive'Access, "loopback send/receive");
      Register_Routine (T, Test_Receive_Timeout'Access, "receive timeout");
   end Register_Tests;

   overriding function Name (T : UDPv4_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.Transports.UDPv4");
   end Name;

end RTPS.Tests.UDPv4;