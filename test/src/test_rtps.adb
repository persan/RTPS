------------------------------------------------------------------------------
--  Test_RTPS -- AUnit harness for the RTPS library test suites.
--
--  Suites: Header, Messages (round-trips + SN-set), Receiver, History,
--  Guid.  Instantiates AUnit's Test_Runner_With_Status generic so the
--  process exit status reflects the outcome.
------------------------------------------------------------------------------

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Suites;
with Ada.Command_Line;

with RTPS.Tests.Header;
with RTPS.Tests.Roundtrip;
with RTPS.Tests.Receiver;
with RTPS.Tests.History;
with RTPS.Tests.Guid;
with RTPS.Tests.UDPv4;
with RTPS.Tests.Proto;
with RTPS.Tests.Discovery;
with RTPS.Tests.Liveliness;
with RTPS.Tests.Payload;

procedure Test_RTPS is

   use AUnit.Test_Suites;
   use all type AUnit.Status;

   function Suite return Access_Test_Suite;
   --  Build the suite: one test-case object per test package.

   function Suite return Access_Test_Suite is
      Result : constant Access_Test_Suite := new Test_Suite;
   begin
      Add_Test (Result, new RTPS.Tests.Header.Header_Test);
      Add_Test (Result, new RTPS.Tests.Roundtrip.Roundtrip_Test);
      Add_Test (Result, new RTPS.Tests.Receiver.Receiver_Test);
      Add_Test (Result, new RTPS.Tests.History.History_Test);
      Add_Test (Result, new RTPS.Tests.Guid.Guid_Test);
      Add_Test (Result, new RTPS.Tests.UDPv4.UDPv4_Test);
      Add_Test (Result, new RTPS.Tests.Proto.Proto_Test);
      Add_Test (Result, new RTPS.Tests.Discovery.Discovery_Test);
      Add_Test (Result, new RTPS.Tests.Liveliness.Liveliness_Test);
      Add_Test (Result, new RTPS.Tests.Payload.Payload_Test);
      return Result;
   end Suite;

   --  Instantiate the status-returning runner on this suite.
   function Run_Suite is new AUnit.Run.Test_Runner_With_Status (Suite);

   Status : AUnit.Status;
   Reporter : aliased AUnit.Reporter.Text.Text_Reporter;

begin
   Status := Run_Suite (Reporter);
   if Status = AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_RTPS;