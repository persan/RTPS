------------------------------------------------------------------------------
--  RTPS.Types -- non-expression bodies
------------------------------------------------------------------------------

package body RTPS.Types is

   function Make_Sequence_Number
     (High : Long; Low : Unsigned_Long) return SequenceNumber_T
   is
      UHigh : Unsigned_Long_Long;
   begin
      if High < 0 then
         --  Reserved value {-1, 0} maps to SEQUENCENUMBER_UNKNOWN (= 0).
         return SEQUENCENUMBER_UNKNOWN;
      else
         UHigh := Unsigned_Long_Long (High);
      end if;
      return SequenceNumber_T (UHigh * 2**32 + Unsigned_Long_Long (Low));
   end Make_Sequence_Number;

   function High_Word (SN : SequenceNumber_T) return Long is
   begin
      if SN = SEQUENCENUMBER_UNKNOWN then
         return -1;
      end if;
      return Long (Unsigned_Long_Long (SN) / 2**32);
   end High_Word;

   function Low_Word (SN : SequenceNumber_T) return Unsigned_Long is
   begin
      if SN = SEQUENCENUMBER_UNKNOWN then
         return 0;
      end if;
      return Unsigned_Long (Unsigned_Long_Long (SN) mod 2**32);
   end Low_Word;

   function Make_UDPv4_Locator
     (A, B, C, D : Octet; Port : Unsigned_Long) return Locator_T
   is
      L : Locator_T;
   begin
      L.Kind := LOCATOR_KIND_UDPv4;
      L.Port := Port;
      L.Address (13) := A;
      L.Address (14) := B;
      L.Address (15) := C;
      L.Address (16) := D;
      return L;
   end Make_UDPv4_Locator;

end RTPS.Types;