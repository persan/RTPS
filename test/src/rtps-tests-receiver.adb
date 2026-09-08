------------------------------------------------------------------------------
--  RTPS.Tests.Receiver -- body
--
--  Multi-submessage message parse, interpreter-state updates, and the
--  8.3.6.3 rule that a message with invalid magic is silently dropped.
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with RTPS.Types;
with RTPS.CDR;
with RTPS.Receiver;
with RTPS.Messages;
with RTPS.Tests.Support;

package body RTPS.Tests.Receiver is

   package T  renames RTPS.Types;
   package M  renames RTPS.Messages;
   package C  renames RTPS.CDR;
   package R  renames RTPS.Receiver;
   use all type T.Octet;
   use all type T.Long;
   use all type T.SequenceNumber_T;
   use all type M.Submessage_Kind;

   --  Shared sink state.
   Sink_Count : Natural := 0;
   Last_Kind  : M.Submessage_Kind := M.KIND_PAD;
   type Submessage_Ref is access M.Submessage_T;
   Last_SM    : Submessage_Ref := null;
   Last_Data  : M.Submessage_T (M.KIND_DATA);

   type Counting_Sink is new R.Sink with null record;

   procedure On_Submessage
     (Self : in out Counting_Sink; SM : M.Submessage_T);
   procedure On_Submessage
     (Self : in out Counting_Sink; SM : M.Submessage_T)
   is
      pragma Unreferenced (Self);
   begin
      Sink_Count := Sink_Count + 1;
      Last_Kind := SM.Kind;
      Last_SM := new M.Submessage_T'(SM);  --  unconstrained copy
      if SM.Kind = M.KIND_DATA or SM.Kind = M.KIND_DATA_FRAG then
         Last_Data := SM;
      end if;
   end On_Submessage;

   ---------------------------------------------------------------------

   procedure Test_Receiver_Parse (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Hdr   : M.Header_T;
      SMs   : constant M.Submessage_Array_Ref :=
        new M.Submessage_Array (1 .. 2);
      Buf   : T.Octet_Buffer;
      State : R.Receiver_State;
      Sink  : aliased Counting_Sink;
      D_Payload : constant T.Octet_Buffer :=
        new T.Octet_Array'(16#01#, 16#02#, 16#03#, 16#04#);
   begin
      declare
         TS : M.Submessage_T (M.KIND_INFO_TS);
         D  : M.Submessage_T (M.KIND_DATA);
      begin
         TS.Endianness := CDR.Little_Endian;
         TS.Timestamp := (16#0102_0304#, 16#0506_0708#);

         D.Endianness := CDR.Little_Endian;
         D.Reader_Id := [16#00#, 16#00#, 16#02#, 16#C7#];
         D.Writer_Id := [16#00#, 16#00#, 16#02#, 16#C2#];
         D.Writer_SN := 42;
         D.Has_Payload := True;
         D.Is_Key := False;
         D.Payload := D_Payload;
         D.Payload_Length := 4;

         SMs (1) := TS;
         SMs (2) := D;
      end;

      Buf := Support.Encode_Message (Hdr, SMs);

      Sink_Count := 0;
      R.Process_Message (Buf.all (1 .. Support.Enc_Len), State, Sink);

      Assert (Sink_Count = 2, "rx count");
      Assert (State.Have_Timestamp
              and State.Timestamp.Seconds = 16#0102_0304#, "rx state ts");
      Assert (Last_Kind = M.KIND_DATA, "rx last kind");
      Assert (Last_Data.Writer_SN = 42, "rx data sn");
      Assert (Last_Data.Payload_Length = 4, "rx data len");
   end Test_Receiver_Parse;

   ---------------------------------------------------------------------

   procedure Test_Bad_Magic_Dropped
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Hdr   : M.Header_T;
      SMs   : constant M.Submessage_Array_Ref :=
        new M.Submessage_Array (1 .. 1);
      Buf   : T.Octet_Buffer;
      State : R.Receiver_State;
      Sink  : aliased Counting_Sink;
      D     : M.Submessage_T (M.KIND_DATA);
   begin
      D.Endianness := CDR.Little_Endian;
      D.Writer_SN := 1;
      D.Has_Payload := False;
      SMs (1) := D;
      Buf := Support.Encode_Message (Hdr, SMs);
      --  Corrupt the magic so the message must be dropped (8.3.6.3).
      Buf.all (2) := 16#00#;

      Sink_Count := 0;
      R.Process_Message (Buf.all (1 .. Support.Enc_Len), State, Sink);
      Assert (Sink_Count = 0, "rx bad magic dropped");
   end Test_Bad_Magic_Dropped;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Receiver_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Receiver_Parse'Access, "receiver parse");
      Register_Routine (T, Test_Bad_Magic_Dropped'Access,
                        "invalid magic dropped");
   end Register_Tests;

   overriding function Name (T : Receiver_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.Receiver");
   end Name;

end RTPS.Tests.Receiver;