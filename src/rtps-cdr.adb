------------------------------------------------------------------------------
--  RTPS.CDR -- body
------------------------------------------------------------------------------

package body RTPS.CDR is

   use all type RTPS.Types.Unsigned_Short;
   use all type RTPS.Types.Unsigned_Long;
   use all type RTPS.Types.Unsigned_Long_Long;
   use all type RTPS.Types.Octet;

   procedure Bind
     (S      : in out Stream;
      Buffer :        Octet_Array_Access;
      Length :        Natural)
   is
   begin
      S.Buffer := Buffer.all'Unrestricted_Access;
      S.First  := Buffer.all'First;
      S.Last   := Buffer.all'First - 1;
      S.Limit  := Buffer.all'First + Length - 1;
      pragma Assert (Length <= Buffer.all'Length);
   end Bind;

   procedure Reset (S : in out Stream) is
   begin
      S.Last := S.First - 1;
   end Reset;

   procedure Align (S : in out Stream; Boundary : Natural) is
      Offset : constant Natural := S.Last - S.First + 1;
      --  0-based offset of the NEXT octet to be accessed, relative to
      --  the start of the stream: equals the number of octets already
      --  written (encode) or consumed (decode).
      Remainder : constant Natural := Offset mod Boundary;
   begin
      if Remainder /= 0 then
         declare
            Pad : constant Natural := Boundary - Remainder;
         begin
            if not Has_Room_For (S, Pad) then
               raise Storage_Exhausted;
            end if;
            for K in 1 .. Pad loop
               S.Last := S.Last + 1;
               S.Buffer.all (S.Last) := 0;
            end loop;
         end;
      end if;
   end Align;

   ---------------------------------------------------------------------
   --  Encoding
   ---------------------------------------------------------------------

   procedure Put_Octet (S : in out Stream; V : RTPS.Types.Octet) is
   begin
      if not Has_Room_For (S, 1) then
         raise Storage_Exhausted;
      end if;
      S.Last := S.Last + 1;
      S.Buffer.all (S.Last) := V;
   end Put_Octet;

   procedure Put_Short (S : in out Stream; V : RTPS.Types.Short;
                        E : Endianness)
   is
      U : constant RTPS.Types.Unsigned_Short :=
        RTPS.Types.Unsigned_Short
          (RTPS.Types.Unsigned_Short'Mod (V));
   begin
      Put_UShort (S, U, E);
   end Put_Short;

   procedure Put_UShort (S : in out Stream; V : RTPS.Types.Unsigned_Short;
                         E : Endianness)
   is
      B0 : constant RTPS.Types.Octet := RTPS.Types.Octet (V / 256);
      B1 : constant RTPS.Types.Octet := RTPS.Types.Octet (V mod 256);
   begin
      Align (S, 2);
      case E is
         when Little_Endian =>
            Put_Octet (S, B1); Put_Octet (S, B0);
         when Big_Endian =>
            Put_Octet (S, B0); Put_Octet (S, B1);
      end case;
   end Put_UShort;

   procedure Put_Long (S : in out Stream; V : RTPS.Types.Long;
                       E : Endianness)
   is
      U : constant RTPS.Types.Unsigned_Long :=
        RTPS.Types.Unsigned_Long (RTPS.Types.Unsigned_Long'Mod (V));
   begin
      Put_ULong (S, U, E);
   end Put_Long;

   procedure Put_ULong (S : in out Stream; V : RTPS.Types.Unsigned_Long;
                        E : Endianness)
   is
      subtype Quad is RTPS.Types.Octet;
      B : array (1 .. 4) of Quad;
      V2 : RTPS.Types.Unsigned_Long := V;
   begin
      Align (S, 4);
      for K in reverse 1 .. 4 loop
         B (K) := Quad (V2 mod 256);
         V2 := V2 / 256;
      end loop;
      case E is
         when Little_Endian =>
            for K in reverse 1 .. 4 loop
               Put_Octet (S, B (K));
            end loop;
         when Big_Endian =>
            for K in 1 .. 4 loop
               Put_Octet (S, B (K));
            end loop;
      end case;
   end Put_ULong;

   procedure Put_Long_Long (S : in out Stream; V : RTPS.Types.Long_Long;
                            E : Endianness)
   is
      U : constant RTPS.Types.Unsigned_Long_Long :=
        RTPS.Types.Unsigned_Long_Long (RTPS.Types.Unsigned_Long_Long'Mod (V));
   begin
      Put_ULong_Long (S, U, E);
   end Put_Long_Long;

   procedure Put_ULong_Long (S : in out Stream;
                             V : RTPS.Types.Unsigned_Long_Long;
                             E : Endianness)
   is
      subtype Quad is RTPS.Types.Octet;
      B : array (1 .. 8) of Quad;
      V2 : RTPS.Types.Unsigned_Long_Long := V;
   begin
      Align (S, 8);
      for K in reverse 1 .. 8 loop
         B (K) := Quad (V2 mod 256);
         V2 := V2 / 256;
      end loop;
      case E is
         when Little_Endian =>
            for K in reverse 1 .. 8 loop
               Put_Octet (S, B (K));
            end loop;
         when Big_Endian =>
            for K in 1 .. 8 loop
               Put_Octet (S, B (K));
            end loop;
      end case;
   end Put_ULong_Long;

   procedure Put_Octets (S : in out Stream; V : RTPS.Types.Octet_Array) is
   begin
      if not Has_Room_For (S, V'Length) then
         raise Storage_Exhausted;
      end if;
      for K in V'Range loop
         S.Last := S.Last + 1;
         S.Buffer.all (S.Last) := V (K);
      end loop;
   end Put_Octets;

   ---------------------------------------------------------------------
   --  Decoding
   ---------------------------------------------------------------------

   procedure Get_Octet (S : in out Stream; V : out RTPS.Types.Octet) is
   begin
      if S.Last = 0 then
         V := S.Buffer.all (S.First);  --  will raise if empty
         S.Last := S.First;
      else
         if S.Last >= S.Buffer.all'Last then
            raise Constraint_Error;
         end if;
         S.Last := S.Last + 1;
      end if;
      V := S.Buffer.all (S.Last);
   end Get_Octet;

   procedure Get_Short (S : in out Stream; V : out RTPS.Types.Short;
                        E : Endianness)
   is
      U : RTPS.Types.Unsigned_Short;
   begin
      Get_UShort (S, U, E);
      V := RTPS.Types.Short (U);
   end Get_Short;

   procedure Get_UShort (S : in out Stream; V : out RTPS.Types.Unsigned_Short;
                         E : Endianness)
   is
      B0, B1 : RTPS.Types.Octet;
      --  B0 = most-significant octet, B1 = least-significant octet.
   begin
      Align (S, 2);
      case E is
         when Little_Endian =>
            Get_Octet (S, B1); Get_Octet (S, B0);
         when Big_Endian =>
            Get_Octet (S, B0); Get_Octet (S, B1);
      end case;
      V := RTPS.Types.Unsigned_Short (B0) * 256
         + RTPS.Types.Unsigned_Short (B1);
   end Get_UShort;

   procedure Get_Long (S : in out Stream; V : out RTPS.Types.Long;
                       E : Endianness)
   is
      U : RTPS.Types.Unsigned_Long;
   begin
      Get_ULong (S, U, E);
      V := RTPS.Types.Long (U);
   end Get_Long;

   procedure Get_ULong (S : in out Stream; V : out RTPS.Types.Unsigned_Long;
                        E : Endianness)
   is
      B : RTPS.Types.Octet;
      U : RTPS.Types.Unsigned_Long := 0;
   begin
      Align (S, 4);
      case E is
         when Little_Endian =>
            for K in 1 .. 4 loop
               Get_Octet (S, B);
               U := U + RTPS.Types.Unsigned_Long (B) * 256**(K - 1);
            end loop;
         when Big_Endian =>
            for K in 1 .. 4 loop
               Get_Octet (S, B);
               U := U * 256 + RTPS.Types.Unsigned_Long (B);
            end loop;
      end case;
      V := U;
   end Get_ULong;

   procedure Get_Long_Long (S : in out Stream; V : out RTPS.Types.Long_Long;
                            E : Endianness)
   is
      U : RTPS.Types.Unsigned_Long_Long;
   begin
      Get_ULong_Long (S, U, E);
      V := RTPS.Types.Long_Long (U);
   end Get_Long_Long;

   procedure Get_ULong_Long (S : in out Stream;
                             V : out RTPS.Types.Unsigned_Long_Long;
                             E : Endianness)
   is
      B : RTPS.Types.Octet;
      U : RTPS.Types.Unsigned_Long_Long := 0;
   begin
      Align (S, 8);
      case E is
         when Little_Endian =>
            for K in 1 .. 8 loop
               Get_Octet (S, B);
               U := U + RTPS.Types.Unsigned_Long_Long (B) * 256**(K - 1);
            end loop;
         when Big_Endian =>
            for K in 1 .. 8 loop
               Get_Octet (S, B);
               U := U * 256 + RTPS.Types.Unsigned_Long_Long (B);
            end loop;
      end case;
      V := U;
   end Get_ULong_Long;

   procedure Get_Octets (S : in out Stream; V : out RTPS.Types.Octet_Array) is
   begin
      if S.Last + V'Length > S.Buffer.all'Length + (S.First - 1) then
         raise Constraint_Error;
      end if;
      for K in V'Range loop
         S.Last := S.Last + 1;
         V (K) := S.Buffer.all (S.Last);
      end loop;
   end Get_Octets;

end RTPS.CDR;