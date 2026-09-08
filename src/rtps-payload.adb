------------------------------------------------------------------------------
--  RTPS.Payload -- body
--
--  Header layout (10.2.1.1/10.2.1.2/10.2.1.3): the identifier octets
--  are NOT endian-swapped (they are a byte pattern, Table 10.1); the
--  options field is a plain ushort, written in the header's own
--  little-endian layout (the 10.2.2.1 example writes 0x00 0x00 for
--  both endiannesses).
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Messages;

package body RTPS.Payload is

   package C renames RTPS.CDR;
   package M renames RTPS.Messages;

   Header_Size : constant := 4;
   --  identifier (2) + options (2).

   use all type T.Octet;
   use type M.Parameter_Array_Ref;

   ---------------------------------------------------------------------

   function Identifier_Endianness
     (Id : Scheme_Id) return C.Endianness
   is
     (if Id (2) = 16#00# or else Id (2) = 16#02#
      then C.Big_Endian else C.Little_Endian);

   function Build_Header
     (Value   : Scheme;
      Little  : Boolean) return Scheme_Id
   is
   begin
      case Value is
         when Scheme_CDR =>
            return (if Little then CDR_LE else CDR_BE);
         when Scheme_PL_CDR =>
            return (if Little then PL_CDR_LE else PL_CDR_BE);
      end case;
   end Build_Header;

   ---------------------------------------------------------------------

   function Encode_CDR
     (Encoded     :        T.Octet_Array;
      Little      :        Boolean;
      Options     :        T.Unsigned_Short := 0)
      return T.Octet_Buffer
   is
      Id    : constant Scheme_Id := Build_Header (Scheme_CDR, Little);
      Total : constant Natural := Header_Size + Encoded'Length;
      Buf   : constant T.Octet_Buffer :=
        new T.Octet_Array (1 .. Total);
      S     : C.Stream;
      use all type T.Octet;
   begin
      C.Bind (S, C.Octet_Array_Access (Buf), Total);
      C.Put_Octet (S, Id (1));
      C.Put_Octet (S, Id (2));
      C.Put_UShort (S, Options, C.Little_Endian);
      C.Put_Octets (S, Encoded);
      return Buf;
   end Encode_CDR;

   procedure Decode_CDR
     (Wire        :        T.Octet_Array;
      Body_Start  :    out Natural;
      Little      :    out Boolean;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean)
   is
      use all type T.Octet;
      Id   : Scheme_Id;
      Copy : constant T.Octet_Buffer := new T.Octet_Array'(Wire);
      S    : C.Stream;
   begin
      Body_Start := 0;
      Little := False;
      Options := 0;
      Ok := False;

      if Wire'Length < Header_Size then
         return;
      end if;

      Id := (Wire (Wire'First), Wire (Wire'First + 1));
      if Id /= CDR_BE and then Id /= CDR_LE then
         return;
      end if;

      C.Bind (S, C.Octet_Array_Access (Copy), Copy.all'Length);
      C.Get_Octet (S, Id (1));
      C.Get_Octet (S, Id (2));
      C.Get_UShort (S, Options, C.Little_Endian);

      Little := (Id = CDR_LE);
      Body_Start := Wire'First + Header_Size;
      Ok := True;
   end Decode_CDR;

   ---------------------------------------------------------------------

   function Encode_PL_CDR
     (List        :        M.Parameter_Array;
      Little      :        Boolean;
      Options     :        T.Unsigned_Short := 0)
      return T.Octet_Buffer
   is
      Id   : constant Scheme_Id := Build_Header (Scheme_PL_CDR, Little);
      Wire : constant T.Octet_Buffer := new T.Octet_Array (1 .. 4096);
      S    : C.Stream;
      Idx  : Natural;
   begin
      C.Bind (S, C.Octet_Array_Access (Wire), Wire.all'Length);
      C.Put_Octet (S, Id (1));
      C.Put_Octet (S, Id (2));
      C.Put_UShort (S, Options, C.Little_Endian);
      M.Put_Parameter_List
        (S, List, (if Little then C.Little_Endian else C.Big_Endian));
      Idx := C.Encoded_Length (S);
      return new T.Octet_Array'(Wire (1 .. Idx));
   end Encode_PL_CDR;

   procedure Decode_PL_CDR
     (Wire        :        T.Octet_Array;
      List        :    out M.Parameter_Array_Ref;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean)
   is
      use all type T.Octet;
      Id    : Scheme_Id;
      Little : Boolean;
   begin
      List := null;
      Options := 0;
      Ok := False;

      if Wire'Length < Header_Size + 4 then
         --  Header + at least the sentinel parameter (4 octets).
         return;
      end if;

      Id := (Wire (Wire'First), Wire (Wire'First + 1));
      if Id /= PL_CDR_BE and then Id /= PL_CDR_LE then
         return;
      end if;

      --  Parse the header directly (Decode_CDR only accepts CDR_*).
      declare
         Copy : constant T.Octet_Buffer := new T.Octet_Array'(Wire);
         HS   : C.Stream;
      begin
         C.Bind (HS, C.Octet_Array_Access (Copy), Copy.all'Length);
         C.Get_Octet (HS, Id (1));
         C.Get_Octet (HS, Id (2));
         C.Get_UShort (HS, Options, C.Little_Endian);
      end;
      Little := (Id = PL_CDR_LE);

      --  Parameter list body follows the header in Copy; rebind and
      --  skip the header.
      declare
         Body_Copy : constant T.Octet_Buffer :=
           new T.Octet_Array'(Wire (Wire'First + Header_Size
                                      .. Wire'Last));
         St   : C.Stream;
      begin
         C.Bind (St, C.Octet_Array_Access (Body_Copy),
                 Body_Copy.all'Length);
         M.Decode_Parameter_List
           (St, List, (if Little then C.Little_Endian else C.Big_Endian));
      end;
      Ok := List /= null;
   end Decode_PL_CDR;

   ---------------------------------------------------------------------

   procedure Decode_Header
     (Wire        :        T.Octet_Array;
      Id          :    out Scheme_Id;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean)
   is
      use all type T.Octet;
      Copy : constant T.Octet_Buffer := new T.Octet_Array'(Wire);
      S    : C.Stream;
   begin
      Id := CDR_BE;
      Options := 0;
      Ok := False;

      if Wire'Length < Header_Size then
         return;
      end if;

      Id := (Wire (Wire'First), Wire (Wire'First + 1));
      if Id /= CDR_BE and then Id /= CDR_LE
        and then Id /= PL_CDR_BE and then Id /= PL_CDR_LE
      then
         return;
      end if;

      C.Bind (S, C.Octet_Array_Access (Copy), Copy.all'Length);
      C.Get_Octet (S, Id (1));
      C.Get_Octet (S, Id (2));
      C.Get_UShort (S, Options, C.Little_Endian);
      Ok := True;
   end Decode_Header;

end RTPS.Payload;