# Input data

## Renewable energy for hydrogen production: Hourly wind generation profile

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

- **Source:** https://mimer.svk.se/ProductionConsumption/ProductionIndex
- **Retrieved:** 05/18/2026
- **Licence / redistribution terms:** Svenska kraftnät
- **Processing applied:** SCALING, UNIT CONVERSION


