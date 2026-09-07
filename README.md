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

Work in progress. The **Messages Module** (clause 8.3 / 9.4.5 wire mapping) is
implemented and round-trip tested in both endiannesses; the Structure Module
(clause 8.2) and the Behavior / Discovery modules are interfaces and data
types only. Not yet a conformant RTPS implementation — no UDP transport,
no discovery protocol, no writer/reader protocol machines.

## Layout

| Path | Contents |
|---|---|
| `src/` | The library (static library project `rtps.gpr`, produces `libRTPS.a`) |
| `test/` | Self-contained test driver (`test_rtps.gpr`) |
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
| `RTPS.Transports` | 9.6 | Transport abstraction (interface only; UDP/IP PSM not yet written) |

## Building

Requires GNAT and GPRbuild (tested with GNAT Pro 27.0w on Windows).

```sh
# library
gprbuild -Prtps.gpr

# tests (produces test/test_rtps.exe)
cd test && gprbuild -Ptest_rtps.gpr && ./test_rtps
```

The test driver prints `PASS/FAIL` per check and exits non-zero on failure.
Run it from the `test/` directory.

## Example

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

## Roadmap

- UDP/IP transport (the PSM of clause 9) using the `RTPS.Transports`
  interface
- StatefulWriter / StatefulReader protocol machines (8.4.9 / 8.4.12)
- SPDP/SEDP discovery endpoints (8.5)
- CDR payload encapsulation for user data (clause 10)

## References

- OMG DDSI-RTPS 2.2: <https://www.omg.org/spec/DDSI-RTPS/2.2>
- DDS 1.4 (the API this protocol serves): <https://www.omg.org/spec/DDS/1.4>