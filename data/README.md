# Input data

## Hourly generation profile

`fn_load_wind` expects a spreadsheet containing an **8760-hour** generation
profile in MW, read from sheet `Blad2`, range `A2:N8761`. The column used
depends on `cfg.power_mode`:

| `cfg.power_mode`   | Column read |
|--------------------|-------------|
| `'Wind'`           | I (`Var9`)  |
| `'Wind and solar'` | J (`Var10`) |
| `'Solar'`          | G (`Var7`)  |
| `'Continuous'`     | none — a flat profile is generated internally |

Point the script at the file by editing one line in Section 0:

```matlab
cfg.wind_data_path = fullfile(fileparts(mfilename('fullpath')), '..', 'data', ...
                              'Calculation MTH.xlsx');
```

### Provenance

- **Source:** [WHERE THE PROFILE CAME FROM — e.g. ENTSO-E Transparency Platform,
  Svenska kraftnät, a specific report, or your own calculation]
- **Retrieved:** [DATE]
- **Licence / redistribution terms:** [FILL IN]
- **Processing applied:** [ANY SCALING, GAP FILLING, UNIT CONVERSION]

### If you cannot redistribute the file

Two options, in order of preference:

1. **Commit a derived CSV.** Most licences permit publishing a single derived
   column even when the full dataset cannot be mirrored, and a plain CSV is far
   more robust than a fixed sheet name and cell range. Export the hourly column
   to `data/generation_profile.csv` (one header row, one value per hour), then
   un-ignore it in `.gitignore` and simplify `fn_load_wind` to a single
   `readmatrix` call.
2. **Ship instructions only.** Leave this file as the retrieval recipe and let
   users run the `'Continuous'` power mode to verify the rest of the chain.
