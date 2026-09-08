------------------------------------------------------------------------------
--  RTPS.Tests.UDPv4 -- loopback checks for the UDPv4 transport
--
--  Spawns two transports on localhost ports, sends a datagram from one
--  to the other, and verifies the payload and the source locator.
------------------------------------------------------------------------------

with AUnit;
with AUnit.Assertions;
use AUnit.Assertions;
with AUnit.Test_Cases;
with RTPS.Types;
with RTPS.Transports.UDPv4;

package RTPS.Tests.UDPv4 is

   type UDPv4_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out UDPv4_Test);
   overriding function Name (T : UDPv4_Test) return AUnit.Message_String;

end RTPS.Tests.UDPv4;