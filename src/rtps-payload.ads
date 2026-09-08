------------------------------------------------------------------------------
--  RTPS.Payload -- Data encapsulation for user data (clause 10)
--
--  The SerializedData of a DATA submessage is opaque to RTPS itself
--  (8.3.5.12); the DDS type-plugin serializes the data.  For
--  interoperability every encapsulation starts with a 2-octet
--  encapsulation scheme identifier (10.2.1.1, Table 10.1):
--
--    CDR_BE    = (16#00#, 16#00#)   OMG CDR, big endian
--    CDR_LE    = (16#00#, 16#01#)   OMG CDR, little endian
--    PL_CDR_BE = (16#00#, 16#02#)  ParameterList over CDR big endian
--    PL_CDR_LE = (16#00#, 16#03#)  ParameterList over CDR little endian
--
--  The identifier is followed by a 16-bit options field (reserved;
--  write 0, do not interpret) and then the CDR-encoded data or the
--  ParameterList.  The identifier octets are a byte pattern carried
--  verbatim (Table 10.1); the byte order of the *payload* is a
--  property described by the identifier, not of it.
--
--  Fragmentation is done after encapsulation (10.2.1.2), so each
--  fragment of a serialized sample starts with the same header.
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Messages;
with RTPS.Types;

package RTPS.Payload is

   package T renames RTPS.Types;

   ---------------------------------------------------------------------
   --  Encapsulation scheme identifiers (Table 10.1)
   ---------------------------------------------------------------------

   type Scheme_Id is array (1 .. 2) of T.Octet;

   CDR_BE    : constant Scheme_Id := (16#00#, 16#00#);
   CDR_LE    : constant Scheme_Id := (16#00#, 16#01#);
   PL_CDR_BE : constant Scheme_Id := (16#00#, 16#02#);
   PL_CDR_LE : constant Scheme_Id := (16#00#, 16#03#);

   type Scheme is (Scheme_CDR, Scheme_PL_CDR);

   ---------------------------------------------------------------------
   --  Encapsulation header (10.2.1.1)
   ---------------------------------------------------------------------

   function Identifier_Endianness
     (Id : Scheme_Id) return RTPS.CDR.Endianness;
   --  The CDR byte order the payload uses, derived from the scheme
   --  identifier (CDR_BE/PL_CDR_BE -> Big_Endian; CDR_LE/PL_CDR_LE ->
   --  Little_Endian).

   function Build_Header
     (Value   : Scheme;
      Little  : Boolean) return Scheme_Id;
   --  The two identifier octets for the given scheme/byte order.

   ---------------------------------------------------------------------
   --  OMG CDR encapsulation (10.2.1.2)
   ---------------------------------------------------------------------

   function Encode_CDR
     (Encoded     :        T.Octet_Array;
      Little      :        Boolean;
      Options     :        T.Unsigned_Short := 0)
      return T.Octet_Buffer;
   --  Wraps an already CDR-encoded value into the CDR encapsulation:
   --  identifier (CDR_BE/CDR_LE) + ushort options + the data.  The
   --  caller serializes the application type with RTPS.CDR (into its
   --  own buffer) and passes the result as Encoded; this package
   --  handles the header.  Caller frees the result.

   procedure Decode_CDR
     (Wire        :        T.Octet_Array;
      Body_Start  :    out Natural;
      Little      :    out Boolean;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean);
   --  Parse the encapsulation header of Wire.  On success Body_Start
   --  is the index (in Wire) of the first octet of the CDR payload
   --  and Little tells the caller which byte order to decode it with.
   --  Ok is False for malformed input (fewer than 4 octets or an
   --  unknown scheme identifier).

   ---------------------------------------------------------------------
   --  ParameterList encapsulation (10.2.1.3)
   ---------------------------------------------------------------------

   function Encode_PL_CDR
     (List        :        RTPS.Messages.Parameter_Array;
      Little      :        Boolean;
      Options     :        T.Unsigned_Short := 0)
      return T.Octet_Buffer;
   --  Wraps a ParameterList into the PL_CDR encapsulation: scheme id
   --  + options + parameter list (9.4.2.11, including the sentinel).
   --  Caller frees the result.

   procedure Decode_PL_CDR
     (Wire        :        T.Octet_Array;
      List        :    out RTPS.Messages.Parameter_Array_Ref;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean);
   --  Parse a PL_CDR payload: header + parameter list.  Ok is False
   --  for malformed input or a non-ParameterList scheme id.

   ---------------------------------------------------------------------
   --  Generic header parse (covers all four schemes of Table 10.1)
   ---------------------------------------------------------------------

   procedure Decode_Header
     (Wire        :        T.Octet_Array;
      Id          :    out Scheme_Id;
      Options     :    out T.Unsigned_Short;
      Ok          :    out Boolean);
   --  Parse identifier + options without dispatching on the scheme.

end RTPS.Payload;