------------------------------------------------------------------------------
--  RTPS.CDR
--
--  Byte-stream primitive operators used by the UDP PSM wire encoding
--  (clause 9.2.2/9.2.3: "Representation of Bits and Bytes").
--
--  All multi-octet RTPS quantities are mapped onto the byte stream in
--  little-endian (when the Submessage EndiannessFlag E = 1) or
--  big-endian (E = 0) order.  Primitive types are aligned to their size
--  relative to the start of the CDR stream.
------------------------------------------------------------------------------

with RTPS.Types;

--  The stream is a bounded buffer; Encode raises Storage_Error when the
--  data does not fit, Decode raises Constraint_Error when the stream is
--  exhausted.
package RTPS.CDR is

   Storage_Exhausted : exception;

   type Endianness is (Big_Endian, Little_Endian);

   type Stream is tagged record
      Buffer : RTPS.Types.Octet_Buffer := null;
      --  Access to the underlying buffer; set via Bind.
      First  : Natural := 1;
      --  Index of first valid octet in Buffer.
      Last   : Natural := 0;
      --  Index of last written octet (encode) / next to read - 1 (decode).
      Limit  : Natural := 0;
      --  Absolute index of the last octet belonging to the current
      --  logical message (may be < Buffer'Last when a datagram is
      --  shorter than the buffer).  Set by Bind from Length.
   end record;

   --  Named access type so callers can bind stack-allocated buffers of
   --  a statically matching subtype:
   type Octet_Array_Access is access all RTPS.Types.Octet_Array;

   type Stream_Ref is access all Stream;

   ---------------------------------------------------------------------
   --  Encoding
   ---------------------------------------------------------------------

   procedure Bind
     (S      : in out Stream;
      Buffer :        Octet_Array_Access;
      Length :        Natural);
   --  Bind an encoder/decoder to a buffer of the given length.

   procedure Reset (S : in out Stream) with Post => S.Last = 0;

   function Encoded_Length (S : Stream) return Natural is (S.Last)
     with Inline;

   procedure Align (S : in out Stream; Boundary : Natural) with
     Pre => Boundary in 1 | 2 | 4 | 8;
   --  Insert pad octets until the next octet index (relative to stream
   --  start, i.e. index First) is aligned to Boundary.

   procedure Put_Octet  (S : in out Stream; V : RTPS.Types.Octet);
   procedure Put_Short  (S : in out Stream; V : RTPS.Types.Short; E : Endianness);
   procedure Put_UShort (S : in out Stream; V : RTPS.Types.Unsigned_Short;
                         E : Endianness);
   procedure Put_Long   (S : in out Stream; V : RTPS.Types.Long; E : Endianness);
   procedure Put_ULong  (S : in out Stream; V : RTPS.Types.Unsigned_Long;
                         E : Endianness);
   procedure Put_Long_Long   (S : in out Stream; V : RTPS.Types.Long_Long;
                              E : Endianness);
   procedure Put_ULong_Long  (S : in out Stream;
                              V : RTPS.Types.Unsigned_Long_Long;
                              E : Endianness);
   procedure Put_Octets (S : in out Stream; V : RTPS.Types.Octet_Array);
   --  Raw copy, no alignment.

   ---------------------------------------------------------------------
   --  Decoding
   ---------------------------------------------------------------------

   procedure Get_Octet  (S : in out Stream; V : out RTPS.Types.Octet);
   procedure Get_Short  (S : in out Stream; V : out RTPS.Types.Short;
                         E : Endianness);
   procedure Get_UShort (S : in out Stream; V : out RTPS.Types.Unsigned_Short;
                         E : Endianness);
   procedure Get_Long   (S : in out Stream; V : out RTPS.Types.Long;
                         E : Endianness);
   procedure Get_ULong  (S : in out Stream; V : out RTPS.Types.Unsigned_Long;
                         E : Endianness);
   procedure Get_Long_Long   (S : in out Stream; V : out RTPS.Types.Long_Long;
                              E : Endianness);
   procedure Get_ULong_Long  (S : in out Stream;
                              V : out RTPS.Types.Unsigned_Long_Long;
                              E : Endianness);
   procedure Get_Octets (S : in out Stream; V : out RTPS.Types.Octet_Array);

   function Has_Room_For (S : Stream; N : Natural) return Boolean is
     (S.Last + N <= S.Buffer'Length) with Inline;

end RTPS.CDR;