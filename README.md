# RTPS — DDS Interoperability Wire Protocol in Ada

An interface to, and partial implementation of, the **Real-time Publish-Subscribe
Protocol (RTPS) 2.2** — the DDS Interoperability Wire Protocol defined by the
Object Management Group in
[DDSI-RTPS 2.2](https://www.omg.org/spec/DDSI-RTPS/2.2) (OMG document
formal/2014-09-01), written in Ada.

The goal is a spec-traceable Ada library: every constant, wire layout, and
reserved value is taken from the normative text of the specification and
cross-referenced to its clause number in the source comments.

## Status

Work in progress. Implemented and AUnit-tested: the **Messages Module**
(clause 8.3 / 9.4.5 wire mapping), the **UDPv4 transport** (clause 9 PSM, on
GNAT.Sockets), the **Reliable StatefulWriter / StatefulReader protocol
machines** (8.4.9.2 / 8.4.12.2) with their proxy window state, and the
**Discovery Module** (8.5): SPDP participant discovery with well-known
multicast announcements and lease expiry, plus SEDP endpoint discovery over
the reliable built-in endpoints. SPDP is exercised in a real discovery
exchange over loopback multicast; the protocol machines in a real reliable
exchange (DATA push → HEARTBEAT → ACKNACK → repair). Not yet conformant: no
liveliness protocol and no CDR payload encapsulation for user data.

## Layout

| Path | Contents |
|---|---|
| `src/` | The library (static library project `rtps.gpr`, produces `libRTPS.a`) |
| `test/` | AUnit test driver (`test_rtps.gpr`) — 17 routines across 8 suites (header, message round-trips, receiver, history, GUID, UDPv4 loopback, protocol machines, discovery) |
| `doc/` | The RTPS 2.2 specification PDF and extracted text |

### Library sources (`src/`)

| Package | Spec clause | Description |
|---|---|---|
| `RTPS.Types` | 8.2.1.2, 9.3 | PIM/PSM types: GUID, EntityId, ProtocolVersion, VendorId, SequenceNumber, Time, Locator; entityKind octets and predefined EntityIds (Tables 9.1/9.2); ParameterIds (Table 9.12); default port formulas (9.6.1.3) |
| `RTPS.CDR` | 9.2 | Byte-stream primitives with CDR alignment and little/big-endian encoding |
| `RTPS.Messages` | 8.3, 9.4.5 | RTPS Header, all 13 submessages with wire encode/decode, SequenceNumberSet/FragmentNumberSet bitmaps, ParameterList |
| `RTPS.Entities` | 8.2 | Structure module: Entity/Participant/Endpoint/Writer/Reader interfaces, GUID ordering |
| `RTPS.History` | 8.2.2 | HistoryCache protected type: Add_Change, Remove_Change, Get_Seq_Num_Min/Max, Find |
| `RTPS.Receiver` | 8.3.4 | Message Receiver: parses messages, maintains interpreter state, dispatches submessages to a Sink callback |
| `RTPS.Transports` | 9.6 | Transport abstraction (interface) |
| `RTPS.Transports.UDPv4` | 9 (PSM) | UDPv4 transport on GNAT.Sockets: Open/Close with SO_REUSEADDR, Send (one datagram per message), Receive with optional timeout, multicast group join/leave |
| `RTPS.Proto` | 8.4.7.5, 8.4.10.4 | ReaderProxy/WriterProxy sequence-number window state: acked/requested/unsent and missing/lost/received/irrelevant transitions (Tables 8.56/8.68) |
| `RTPS.StatefulWriter` | 8.4.7.4, 8.4.9.2 | Reliable StatefulWriter machine: match management, DATA/GAP push (T4/T12), periodic HEARTBEAT with FinalFlag NOT_SET (T7), ACKNACK processing (T8/T10), repair resend (T12) |
| `RTPS.StatefulReader` | 8.4.10.3, 8.4.12.2 | Reliable StatefulReader machine: HEARTBEAT handling (T7), DATA into reader cache (T8), GAP irrelevance marking (T9), ACKNACK construction (T5) |
| `RTPS.Discovery.Data` | 8.5.3.2, 8.5.4.4, 9.6.2.2 | SPDPdiscoveredParticipantData / DiscoveredWriterData / DiscoveredReaderData with their ParameterList wire mapping (Table 9.12 ParameterIds) |
| `RTPS.Discovery.SPDP` | 8.5.3 | Simple Participant Discovery Protocol: periodic announcements to the well-known multicast locator 239.255.0.1 (9.6.1.4.1), participant table keyed by GUID with leaseDuration expiry (8.5.3.3.2) |
| `RTPS.Discovery.SEDP` | 8.5.4 | Simple Endpoint Discovery Protocol: reliable built-in endpoints on the protocol machines, participant matching (8.5.5.1/8.5.5.2), local endpoint registration, same-topic reliable matching rule |

## Building

Requires GNAT and GPRbuild (tested with GNAT Pro 27.0w on Windows, and
gnat_native 15 / gprbuild 25 via Alire on Linux CI). The crate builds
with `alr build`; AUnit is fetched automatically as a test dependency.

```sh
# library
gprbuild -Prtps.gpr

# AUnit test driver (produces test/test_rtps[.exe])
cd test && gprbuild -Ptest_rtps.gpr && ./test_rtps
```

The test driver runs the AUnit suites and exits non-zero on failure.

## Example

Encoding a Heartbeat submessage into a datagram:

```ada
with RTPS.Types;  use RTPS.Types;
with RTPS.CDR;    use RTPS.CDR;
with RTPS.Messages;

procedure Send_Heartbeat is
   use type Octet;
   Hdr  : Messages.Header_T;
   SMs  : constant Messages.Submessage_Array_Ref :=
            new Messages.Submessage_Array (1 .. 1);
   Buf  : Octet_Array_Access := new Octet_Array (1 .. 65_507);
   S    : Stream;
   HB   : Messages.Submessage_T (Messages.KIND_HEARTBEAT);
begin
   HB.Endianness := Little_Endian;
   HB.Reader_Id := (16#00#, 16#00#, 16#01#, 16#C7#);  -- built-in reader
   HB.Writer_Id := (16#00#, 16#00#, 16#01#, 16#C2#);  -- built-in writer
   HB.First_SN  := 5;
   HB.Last_SN   := 10;
   HB.Final     := True;

   Bind (S, Buf, Buf'Length);
   Messages.Encode_Header   (S, Hdr);
   Messages.Encode_Submessage (S, HB, Last_Submessage => True);
   --  Buf (1 .. S.Last) is the wire message
end Send_Heartbeat;
```

Sending and receiving real datagrams over the UDPv4 transport:

```ada
with RTPS.Types;
with RTPS.Transports.UDPv4;

procedure UDP_Loop is
   package U renames RTPS.Transports.UDPv4;
   use type RTPS.Types.Octet;

   Tx, Rx : U.UDPv4_Transport;
   Item   : RTPS.Transports.Received_Message;
   Msg    : constant RTPS.Types.Octet_Array := (16#52#, 16#54#, 16#50#, 16#53#);
begin
   Rx.Open (Port => 7411);                  -- binds 0.0.0.0:7411
   Tx.Open (Port => 0);                     -- ephemeral source port

   Tx.Send (Dest => RTPS.Types.Make_UDPv4_Locator (127, 0, 0, 1, Rx.Local_Port),
            Data => Msg);

   Rx.Receive (Item, Timeout => 2.0);       -- 0.0 = block forever
   --  Item.Length = 4, Item.Data holds the message,
   --  Item.Source_Loc is the sender's UDPv4 locator.

   Rx.Close;
   Tx.Close;
end UDP_Loop;
```

Reliable writer → reader exchange with the protocol machines:

```ada
with RTPS.Types;
with RTPS.History;
with RTPS.StatefulWriter;
with RTPS.StatefulReader;
with RTPS.Transports;
with RTPS.Transports.UDPv4;

procedure Reliable_Exchange is
   package SW renames RTPS.StatefulWriter;
   package SR renames RTPS.StatefulReader;
   package U  renames RTPS.Transports.UDPv4;
   use type RTPS.Types.Octet;

   Writer_Cache : constant RTPS.History.History_Cache_Ref :=
     new RTPS.History.History_Cache (Capacity => 32);
   Reader_Cache : constant RTPS.History.History_Cache_Ref :=
     new RTPS.History.History_Cache (Capacity => 32);

   Writer_Guid : constant RTPS.Types.GUID_T :=
     (Guid_Prefix => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      Entity_Id   => [0, 0, 1, 16#C2#]);   -- built-in writer id
   Reader_Guid : constant RTPS.Types.GUID_T :=
     (Guid_Prefix => [21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32],
      Entity_Id   => [0, 0, 1, 16#C7#]);   -- built-in reader id

   Writer : SW.Writer_State;
   Reader : SR.Reader_State;
   Tx     : aliased U.UDPv4_Transport;
   Change : RTPS.History.Cache_Change_Ref;
   Ack    : Boolean;
   Handled: Boolean;
begin
   SW.New_Writer  (Writer, Writer_Guid, Writer_Cache);
   SR.New_Reader  (Reader, Reader_Guid, Reader_Cache);
   Tx.Open (Port => 0);
   SW.Open (Writer, Tx'Access);

   --  Discovery would do this:
   SR.Matched_Writer_Add (Reader, Writer_Guid, Tx.Local_Port);
   SW.Matched_Reader_Add
     (Writer,
      Proxy        => (Remote_Reader_Guid => Reader_Guid, others => <>),
      Window_First => 1,
      Window_Last  => 8);

   --  DDS writes; the writer pushes DATA to the reader.
   Writer_Cache.Add_Change
     (Kind => RTPS.Types.ALIVE, Write_Time => RTPS.Types.TIME_ZERO,
      Instance => 0, Data => null, Data_Length => 0, Change => Change);
   SW.On_New_Change (Writer, Change.all.SN);
   SW.Push_Next (Writer, Reader_Guid);

   --  Reader side: HEARTBEAT triggers the ACKNACK machinery.
   SW.Send_Heartbeat (Writer);
   SR.On_Heartbeat (Reader, Writer_Guid.Entity_Id, 1, 1,
                    Final => False, Liveliness => False, Ack => Ack);
   --  Ack = True: the reader is missing SN 1 and must answer with an
   --  ACKNACK (SR.Make_Acknack builds it, the writer's On_Acknack
   --  processes it and Push_Next (For_Request => True) resends).

   --  Reader side, on receiving the repair DATA:
   SR.On_Data (Reader, Writer_Guid.Entity_Id,
               SN => 1, Payload => null, Payload_Length => 0,
               Handled => Handled);
end Reliable_Exchange;
```

Two participants discovering each other with SPDP:

```ada
with RTPS.Types;
with RTPS.Discovery.SPDP;
with RTPS.Transports.UDPv4;

procedure Spdp_Discovery is
   package SP renames RTPS.Discovery.SPDP;
   package U  renames RTPS.Transports.UDPv4;

   P    : SP.Participant_State;
   Tx   : aliased U.UDPv4_Transport;
   Item : RTPS.Transports.Received_Message;
   Fresh : Boolean;
   Guid  : RTPS.Types.GUID_T;
begin
   SP.New_Participant
     (P,
      Guid_Prefix    => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      Domain_Id      => 0,
      Participant_Id => 0,
      Lease_Duration => 100.0,   --  9.6.1.4 default
      Resend_Period  => 30.0);   --  9.6.1.4.2 default

   --  Listen on the well-known SPDP multicast port of domain 0
   --  (PB + DG*domainId + d0 = 7400) and join 239.255.0.1.
   Tx.Open (Port => RTPS.Types.SPDP_Multicast_Port (0));
   Tx.Join_Group
     (Group =>
        (Kind    => RTPS.Types.LOCATOR_KIND_UDPv4,
         Address => RTPS.Types.SPDP_Multicast_Addr,
         Port    => RTPS.Types.SPDP_Multicast_Port (0)));
   SP.Open (P, Tx'Access);

   --  Periodically (application-driven):
   if SP.Needs_Announce (P, Now => 30.0) then
      SP.Announce (P);          --  8.5.3.1: unsent_changes_reset
   end if;

   --  On a received datagram:
   loop
      Tx.Receive (Item, Timeout => 1.0);
      exit when Item.Length = 0;
      SP.On_Data (P, Item.Data (1 .. Item.Length),
                  Src_Addr => Item.Source_Loc.Address,
                  Src_Port => Item.Source_Loc.Port,
                  Fresh => Fresh, Guid => Guid);
      --  Fresh = True: configure the SEDP machines for Guid (8.5.5.1).
   end loop;

   --  Periodically: SP.Expire_Stale (P, Now) drops expired leases
   --  (8.5.3.3.2).
end Spdp_Discovery;
```

## Design notes

- **Spec traceability** — types and constants carry the clause/table they
  come from (e.g. `PID_SENTINEL` → Table 9.12, `octetsToNextHeader` →
  9.4.5.1.3), so the code can be audited against the normative text.
- **Variant record per submessage** — one `Submessage_T` record with a
  `Submessage_Kind` discriminant covers all kinds; fields that share the
  same wire role (readerId, writerId, writerSN, count) are common
  components.
- **Endian explicit** — endianness is a per-submessage runtime value
  (the protocol's EndiannessFlag), not a compile-time choice.
- **No heap in the hot path** — the encoder writes into a caller-provided
  buffer; sequence-number sets are modeled as fixed 256-bit bitmaps.
- **One datagram per message** — the UDPv4 transport maps one RTPS
  Message to exactly one UDP datagram (clause 9.5); locator→sockaddr
  conversion enforces the 9.3.2 rule (12 zero octets + a.b.c.d).
- **Window-based proxy state** — each ReaderProxy/WriterProxy keeps a
  `[First_SN .. Last_SN]` window with a parallel status array instead of
  open-ended change lists; HEARTBEAT `lost_changes_update` slides the
  window base forward, bounding memory per matched endpoint.
- **Transport-agnostic protocol machines** — the writer sends through
  the abstract `Transport` interface, so the same StatefulWriter/
  StatefulReader work over UDPv4, loopback, or any future PSM.
- **Discovery rides standard DATA** — SPDP/SEDP payloads are plain
  ParameterLists inside DATA submessages (9.6.2.2), so the discovery
  protocols reuse the same encoder/decoder machinery as user traffic.

## Roadmap

- Writer liveliness protocol (8.4.13)
- CDR payload encapsulation for user data (clause 10)
- GAP coalescing for runs of irrelevant sequence numbers (8.4.9.2.12 note)

## References

- OMG DDSI-RTPS 2.2: <https://www.omg.org/spec/DDSI-RTPS/2.2>
- DDS 1.4 (the API this protocol serves): <https://www.omg.org/spec/DDS/1.4>