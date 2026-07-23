# References

This directory contains versioned reference facts consumed by ORCHIDEE. These
tables describe code systems or hospital structures; they do not encode
patient-level data or ORCHIDEE normalization decisions.

- `consores/` contains the TA/DE code catalogues used by the RATB perimeter.
- `rouen/` contains non-sensitive, Rouen-specific unit and establishment
  references used only by the Rouen adapter.

Other hospitals do not need to replace or provide the Rouen references. Their
site adapters provide the portable `unit_mapping` handoff block instead.
