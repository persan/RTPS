------------------------------------------------------------------------------
--  RTPS.Discovery.Data -- body
------------------------------------------------------------------------------

with Ada.Unchecked_Deallocation;

package body RTPS.Discovery.Data is

   use all type T.Octet;
   use all type T.Unsigned_Long;
   use all type T.Unsigned_Short;
   use all type T.ParameterId_T;
   use type T.Octet_Buffer;
   use type M.Parameter_Array_Ref;

   subtype ULong is T.Unsigned_Long;
   subtype UShort is T.Unsigned_Short;

   procedure Free is new Ada.Unchecked_Deallocation
     (M.Parameter_Array, M.Parameter_Array_Ref);

   function To_String_Parameter
     (Id : T.ParameterId_T; Src : T.Octet_Array; Len : Natural)
      return M.Parameter_T;

   function To_String_Parameter
     (Id : T.ParameterId_T; Src : T.Octet_Array; Len : Natural)
      return M.Parameter_T
   is
      V : constant T.Octet_Buffer := new T.Octet_Array (1 .. Len);
   begin
      V.all := Src (1 .. Len);
      return (Parameter_Id => Id, Length => UShort (Len), Value => V);
   end To_String_Parameter;

   ---------------------------------------------------------------------

   function Parameter_Locator
     (Id : T.ParameterId_T; Port : ULong) return M.Parameter_T
   is
      --  Locator_t over UDPv4: kind(4) + 12 octets + port(4)... wire
      --  form is kind + address(16) + port = 24 octets (9.3.2).  The
      --  address is 0.0.0.0: filled in from the datagram source by the
      --  receiving side.
      V : constant T.Octet_Buffer := new T.Octet_Array'(1 .. 24 => 0);
      Kind_Bytes : constant T.Octet_Array (1 .. 4) :=
        (0, 0, 1, 0);  --  LOCATOR_KIND_UDPv4 = 1, little endian
      Port_Bytes : constant T.Octet_Array (1 .. 4) :=
        (T.Octet (Port and 16#FF#),
         T.Octet ((Port / 2**8) and 16#FF#),
         T.Octet ((Port / 2**16) and 16#FF#),
         T.Octet ((Port / 2**24) and 16#FF#));
   begin
      V (1 .. 4) := Kind_Bytes;
      V (21 .. 24) := Port_Bytes;
      return (Parameter_Id => Id, Length => 24, Value => V);
   end Parameter_Locator;

   function Parameter_ULong
     (Id : T.ParameterId_T; Value : ULong) return M.Parameter_T;

   function Parameter_ULong
     (Id : T.ParameterId_T; Value : ULong) return M.Parameter_T
   is
      V : constant T.Octet_Buffer := new T.Octet_Array'(1 .. 4 => 0);
   begin
      V (1) := T.Octet (Value and 16#FF#);
      V (2) := T.Octet ((Value / 2**8) and 16#FF#);
      V (3) := T.Octet ((Value / 2**16) and 16#FF#);
      V (4) := T.Octet ((Value / 2**24) and 16#FF#);
      return (Parameter_Id => Id, Length => 4, Value => V);
   end Parameter_ULong;

   function Parameter_Time
     (Id : T.ParameterId_T; Value : T.Time_T) return M.Parameter_T;

   function Parameter_Time
     (Id : T.ParameterId_T; Value : T.Time_T) return M.Parameter_T
   is
      V : constant T.Octet_Buffer := new T.Octet_Array'(1 .. 8 => 0);
      Sec : constant ULong := ULong (Value.Seconds);
   begin
      V (1) := T.Octet (Value.Fraction and 16#FF#);
      V (2) := T.Octet ((Value.Fraction / 2**8) and 16#FF#);
      V (3) := T.Octet ((Value.Fraction / 2**16) and 16#FF#);
      V (4) := T.Octet ((Value.Fraction / 2**24) and 16#FF#);
      V (5) := T.Octet (Sec and 16#FF#);
      V (6) := T.Octet ((Sec / 2**8) and 16#FF#);
      V (7) := T.Octet ((Sec / 2**16) and 16#FF#);
      V (8) := T.Octet ((Sec / 2**24) and 16#FF#);
      return (Parameter_Id => Id, Length => 8, Value => V);
   end Parameter_Time;

   function Parameter_Guid
     (Id : T.ParameterId_T; Guid : T.GUID_T) return M.Parameter_T;

   function Parameter_Guid
     (Id : T.ParameterId_T; Guid : T.GUID_T) return M.Parameter_T
   is
      V : constant T.Octet_Buffer := new T.Octet_Array (1 .. 16);
   begin
      for K in 1 .. 12 loop
         V (K) := Guid.Guid_Prefix (K);
      end loop;
      for K in 1 .. 4 loop
         V (13 + K - 1) := Guid.Entity_Id (K);
      end loop;
      return (Parameter_Id => Id, Length => 16, Value => V);
   end Parameter_Guid;

   function Get_ULong
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : ULong := 0) return ULong;

   function Get_ULong
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : ULong := 0) return ULong
   is
      use type T.ParameterId_T;
   begin
      if List = null then
         return Default;
      end if;
      for P of List.all loop
         if P.Parameter_Id = Id and then P.Length >= 4
           and then P.Value /= null
         then
            return ULong (P.Value (P.Value'First)) or
              ULong (P.Value (P.Value'First + 1)) * 2**8 or
              ULong (P.Value (P.Value'First + 2)) * 2**16 or
              ULong (P.Value (P.Value'First + 3)) * 2**24;
         end if;
      end loop;
      return Default;
   end Get_ULong;

   function Get_Locator_Port
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : ULong := 0) return ULong;

   function Get_Locator_Port
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : ULong := 0) return ULong
   is
      use type T.ParameterId_T;
   begin
      if List = null then
         return Default;
      end if;
      for P of List.all loop
         if P.Parameter_Id = Id and then P.Length >= 24
           and then P.Value /= null
         then
            --  Locator_t wire (9.3.2): kind(4) + address(16) +
            --  port(4) at octets 21..24, little endian.
            return ULong (P.Value (P.Value'First + 20)) or
              ULong (P.Value (P.Value'First + 21)) * 2**8 or
              ULong (P.Value (P.Value'First + 22)) * 2**16 or
              ULong (P.Value (P.Value'First + 23)) * 2**24;
         end if;
      end loop;
      return Default;
   end Get_Locator_Port;

   function Get_Time
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : T.Time_T) return T.Time_T;

   function Get_Time
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : T.Time_T) return T.Time_T
   is
      use type T.ParameterId_T;
      Frac : ULong := 0;
      Sec  : ULong := 0;
   begin
      if List = null then
         return Default;
      end if;
      for P of List.all loop
         if P.Parameter_Id = Id and then P.Length >= 8
           and then P.Value /= null
         then
            Frac :=
              ULong (P.Value (P.Value'First)) or
              ULong (P.Value (P.Value'First + 1)) * 2**8 or
              ULong (P.Value (P.Value'First + 2)) * 2**16 or
              ULong (P.Value (P.Value'First + 3)) * 2**24;
            Sec :=
              ULong (P.Value (P.Value'First + 4)) or
              ULong (P.Value (P.Value'First + 5)) * 2**8 or
              ULong (P.Value (P.Value'First + 6)) * 2**16 or
              ULong (P.Value (P.Value'First + 7)) * 2**24;
            return (Seconds => T.Long (Sec), Fraction => Frac);
         end if;
      end loop;
      return Default;
   end Get_Time;

   function Get_Guid
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : T.GUID_T) return T.GUID_T;

   function Get_Guid
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Default : T.GUID_T) return T.GUID_T
   is
      use type T.ParameterId_T;
      G : T.GUID_T := Default;
   begin
      if List = null then
         return Default;
      end if;
      for P of List.all loop
         if P.Parameter_Id = Id and then P.Length >= 16
           and then P.Value /= null
         then
            for K in 1 .. 12 loop
               G.Guid_Prefix (K) := P.Value (P.Value'First + K - 1);
            end loop;
            for K in 1 .. 4 loop
               G.Entity_Id (K) := P.Value (P.Value'First + 12 + K - 1);
            end loop;
            return G;
         end if;
      end loop;
      return Default;
   end Get_Guid;

   function Get_String
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Dst : out T.Octet_Array; Len : out Natural) return Boolean;

   function Get_String
     (List : M.Parameter_Array_Ref; Id : T.ParameterId_T;
      Dst : out T.Octet_Array; Len : out Natural) return Boolean
   is
      use type T.ParameterId_T;
   begin
      Len := 0;
      if List = null then
         return False;
      end if;
      for P of List.all loop
         if P.Parameter_Id = Id and then P.Value /= null
           and then P.Length > 0
         then
            Len := Natural'Min (Dst'Length, Natural (P.Length));
            Dst (1 .. Len) :=
              P.Value (P.Value'First .. P.Value'First + Len - 1);
            return True;
         end if;
      end loop;
      return False;
   end Get_String;

   ---------------------------------------------------------------------

   function Encode_Participant_Data
     (D    : Participant_Data;
      Guid : T.GUID_T)
      return M.Parameter_Array_Ref
   is
      List : constant M.Parameter_Array_Ref :=
        new M.Parameter_Array (1 .. 11);
      K : Natural := 0;
   begin
      --  PID_PROTOCOL_VERSION (Table 9.12): major, minor octets.
      declare
         V : constant T.Octet_Buffer :=
           new T.Octet_Array'
             (1 => D.Protocol_Version.Major,
              2 => D.Protocol_Version.Minor,
              3 => 0, 4 => 0);
      begin
         K := K + 1;
         List (K) := (Parameter_Id => T.PID_PROTOCOL_VERSION,
                      Length => 4, Value => V);
      end;

      --  PID_VENDORID: two octets.
      declare
         V : constant T.Octet_Buffer :=
           new T.Octet_Array'(1 => D.Vendor_Id (1),
                              2 => D.Vendor_Id (2),
                              3 => 0, 4 => 0);
      begin
         K := K + 1;
         List (K) := (Parameter_Id => T.PID_VENDORID,
                      Length => 4, Value => V);
      end;

      K := K + 1;
      List (K) := Parameter_Guid (T.PID_PARTICIPANT_GUID, Guid);

      K := K + 1;
      List (K) := Parameter_ULong
        (T.PID_BUILTIN_ENDPOINT_SET, ULong (D.Available_Builtin_Endpoints));

      K := K + 1;
      List (K) := Parameter_Locator
        (T.PID_METATRAFFIC_UNICAST_LOCATOR, D.Metatraffic_Unicast_Port);

      K := K + 1;
      List (K) := Parameter_Locator
        (T.PID_METATRAFFIC_MULTICAST_LOCATOR, D.Metatraffic_Multicast_Port);

      K := K + 1;
      List (K) := Parameter_Locator
        (T.PID_DEFAULT_UNICAST_LOCATOR, D.Default_Unicast_Port);

      K := K + 1;
      List (K) := Parameter_Locator
        (T.PID_DEFAULT_MULTICAST_LOCATOR, D.Default_Multicast_Port);

      K := K + 1;
      List (K) := Parameter_ULong
        (T.PID_PARTICIPANT_MANUAL_LIVELINESS_COUNT,
         ULong (D.Manual_Liveliness_Count));

      K := K + 1;
      List (K) := Parameter_Time
        (T.PID_PARTICIPANT_LEASE_DURATION, D.Lease_Duration);

      --  PID_EXPECTS_INLINE_QOS: boolean (4 octets).
      declare
         V : constant T.Octet_Buffer :=
           new T.Octet_Array'(1 .. 4 =>
             (if D.Expects_Inline_Qos then 1 else 0));
      begin
         K := K + 1;
         List (K) := (Parameter_Id => T.PID_EXPECTS_INLINE_QOS,
                      Length => 4, Value => V);
      end;

      return List;
   end Encode_Participant_Data;

   function Decode_Participant_Data
     (List : M.Parameter_Array_Ref) return Participant_Data
   is
      D : Participant_Data;
      use type T.ParameterId_T;
   begin
      if List /= null then
         for P of List.all loop
            if P.Parameter_Id = T.PID_PROTOCOL_VERSION
              and then P.Value /= null and then P.Length >= 2
            then
               D.Protocol_Version :=
                 (Major => P.Value (P.Value'First),
                  Minor => P.Value (P.Value'First + 1));
            elsif P.Parameter_Id = T.PID_VENDORID
              and then P.Value /= null and then P.Length >= 2
            then
               D.Vendor_Id :=
                 (P.Value (P.Value'First), P.Value (P.Value'First + 1));
            elsif P.Parameter_Id = T.PID_EXPECTS_INLINE_QOS
              and then P.Value /= null and then P.Length >= 4
            then
               D.Expects_Inline_Qos :=
                 P.Value (P.Value'First) /= 0
                 or else P.Value (P.Value'First + 1) /= 0
                 or else P.Value (P.Value'First + 2) /= 0
                 or else P.Value (P.Value'First + 3) /= 0;
            end if;
         end loop;
      end if;

      D.Available_Builtin_Endpoints := T.BuiltinEndpointSet_T (Get_ULong
        (List, T.PID_BUILTIN_ENDPOINT_SET));
      D.Manual_Liveliness_Count := T.Count_T (Get_ULong
        (List, T.PID_PARTICIPANT_MANUAL_LIVELINESS_COUNT));
      D.Metatraffic_Unicast_Port := Get_Locator_Port
        (List, T.PID_METATRAFFIC_UNICAST_LOCATOR);
      D.Metatraffic_Multicast_Port := Get_Locator_Port
        (List, T.PID_METATRAFFIC_MULTICAST_LOCATOR);
      D.Default_Unicast_Port := Get_Locator_Port
        (List, T.PID_DEFAULT_UNICAST_LOCATOR);
      D.Default_Multicast_Port := Get_Locator_Port
        (List, T.PID_DEFAULT_MULTICAST_LOCATOR);
      D.Lease_Duration := Get_Time
        (List, T.PID_PARTICIPANT_LEASE_DURATION, D.Lease_Duration);
      --  PID_PARTICIPANT_GUID is consumed by the SPDP machine itself
      --  (it keys the discovered-participant table).
      return D;
   end Decode_Participant_Data;

   ---------------------------------------------------------------------

   function Encode_Writer_Data
     (D : Endpoint_Data) return M.Parameter_Array_Ref
   is
      List : constant M.Parameter_Array_Ref :=
        new M.Parameter_Array (1 .. 6);
      K : Natural := 0;
   begin
      K := K + 1;
      List (K) := To_String_Parameter
        (T.PID_TOPIC_NAME, D.Topic_Name, D.Topic_Len);
      K := K + 1;
      List (K) := To_String_Parameter
        (T.PID_TYPE_NAME, D.Type_Name, D.Type_Len);
      K := K + 1;
      List (K) := Parameter_Guid
        (T.PID_KEY_HASH, D.Writer_Or_Reader_Guid);
      K := K + 1;
      List (K) := Parameter_Locator
        (T.PID_UNICAST_LOCATOR, D.Unicast_Port);
      K := K + 1;
      List (K) := Parameter_ULong
        (T.PID_RELIABILITY, (if D.Reliability then 1 else 0));
      K := K + 1;
      List (K) := Parameter_ULong
        (T.PID_EXPECTS_INLINE_QOS, (if D.Expects_Inline_Qos then 1 else 0));
      return List;
   end Encode_Writer_Data;

   function Decode_Writer_Data
     (List : M.Parameter_Array_Ref) return Endpoint_Data
   is
      D : Endpoint_Data;
      U : ULong;
   begin
      if Get_String (List, T.PID_TOPIC_NAME, D.Topic_Name, D.Topic_Len) then
         null;
      end if;
      if Get_String (List, T.PID_TYPE_NAME, D.Type_Name, D.Type_Len) then
         null;
      end if;
      D.Writer_Or_Reader_Guid :=
        Get_Guid (List, T.PID_KEY_HASH, T.GUID_UNKNOWN);
      D.Unicast_Port := Get_Locator_Port (List, T.PID_UNICAST_LOCATOR);
      U := Get_ULong (List, T.PID_RELIABILITY);
      D.Reliability := (U /= 0);
      U := Get_ULong (List, T.PID_EXPECTS_INLINE_QOS);
      D.Expects_Inline_Qos := (U /= 0);
      return D;
   end Decode_Writer_Data;

   function Encode_Reader_Data
     (D : Endpoint_Data) return M.Parameter_Array_Ref
   is
   begin
      --  Same parameter set (Table 9.13: the parameter set is shared;
      --  the key disambiguates the endpoint).
      return Encode_Writer_Data (D);
   end Encode_Reader_Data;

   function Decode_Reader_Data
     (List : M.Parameter_Array_Ref) return Endpoint_Data
   is
   begin
      return Decode_Writer_Data (List);
   end Decode_Reader_Data;

end RTPS.Discovery.Data;