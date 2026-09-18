# Spatial Feasibility and Infrastructure Requirements for E-Fuel Supply Chains in Ports

MATLAB code accompanying the MSc thesis *"Spatial Feasibility and Infrastructure Requirements for E-Fuel Supply Chains in Ports"* by ANTON NEIDERT, Department of Environmental and Energy Sciences, CHALMERS UNIVERSITY OF TECHNOLOGY, 2026.

The model sizes and costs alternative marine fuel supply chains for a port bunkering demand, comparing four scenarios and 2 e-fuel supply configurations:

| Scenario | Fuel     | Share of baseline MGO demand replaced |
|----------|----------|---------------------------------------|
| A        | Methanol | 25 %                                  |
| B        | Ammonia  | 25 %                                  |
| C        | Methanol | 100 %                                 |
| D        | Ammonia  | 100 %                                 |

**Config 1: E-Fuel Import and Distribution Hub.**
Port functioning as a distribution and refuelling node for fuel produced off-site.

**Config 2: On-site Hydrogen and E-Fuel Production Hub.**
Hydrogen is produced from renewable electricity and converted on site into e-methanol or e-ammonia.


> **Full text of the thesis:** [LINK TO UNIVERSITY REPOSITORY / DOI]

---

## Repository contents

```
.
├── src/
│   └── run_supply_chain_model.m   Main script (configuration + model + all figures)
├── data/
│   └── README.md                  How to obtain the hourly generation profile
├── figures/                       Output figures (generated, not tracked)
├── CITATION.cff                   Citation metadata
├── LICENSE                        [LICENSE NAME]
└── README.md
```

## Requirements

- MATLAB **[YOUR VERSION, e.g. R2023b]** or newer. Run `ver` in MATLAB and paste
  the version you actually used — this is the single most useful line in the
  whole README for anyone trying to reproduce the results.
- Toolboxes: **[LIST, or "none — base MATLAB only"]**. Check with
  `matlab.codetools.requiredFilesAndProducts('src/run_supply_chain_model.m')`.

## How to run

1. Clone the repository:
   ```bash
   git clone https://github.com/[USER]/[REPO].git
   cd [REPO]
   ```
2. Place the generation profile in `data/` (see `data/README.md`).
3. In MATLAB, `cd` to the repository root and run:
   ```matlab
   cd src
   run_supply_chain_model
   ```

A full run prints the sizing and cost tables to the Command Window and opens the
figures reported in Chapter 4. Expected runtime: **[X minutes]** on
**[YOUR MACHINE, e.g. a 2022 laptop, 16 GB RAM]**.

## Configuration

All switches live in **Section 0** at the top of the script; nothing downstream
needs editing:

| Setting                  | Options                                            | Reported value |
|--------------------------|----------------------------------------------------|----------------|
| `cfg.selected_elec`      | `1` alkaline, `2` PEM, `3` SOEC                    | `2`            |
| `cfg.power_mode`         | `'Wind'`, `'Wind and solar'`, `'Solar'`, `'Continuous'` | `'Wind'`   |
| `cfg.terminal_mode`      | `'export'`, `'bunker'`                             | `'export'`     |
| `cfg.storage_basis_opt2` | `'import'`, `'production'`                         | `'import'`     |
| `cfg.siding_policy`      | `'fitted'`, `'standard'`                           | `'fitted'`     |
| `cfg.run_sensitivity`    | `true` / `false`                                   | `true`         |
| `cfg.run_fit_diagnostics`| `true` / `false`                                   | `true`         |

Setting `cfg.power_mode = 'Continuous'` removes the dependency on the external
generation profile entirely (a flat 1 GW profile is used), so the script runs
out of the box without any data file.

## Map from code to thesis

Equation and table numbers are cited inline throughout the script. The main
correspondences:

| Code                     | Thesis                                        |
|--------------------------|-----------------------------------------------|
| Section 0                | Run configuration (not in thesis)             |
| Section 3.4.1            | Global inputs, Tables B.1–B.12                |
| Section 3.6.4a           | Generation resource, Eqs. 3.68–3.71           |
| `fn_run_scenario`        | Chain calculation, Sections 3.4–3.6           |
| `fn_sensitivity`, `fn_tornado_filtered` | Section 4.7 sensitivity analysis |
| `fn_fit_diagnostics`     | Appendix B.2 curve fits                       |
| `fn_plot_*`              | Figures in Chapter 4                          |

*(Fill in the remaining rows — this table is what makes the repo genuinely
useful to an examiner or a follow-on student.)*

## Citation

If you use this code, please cite the thesis:

> [YOUR NAME] ([YEAR]). *[THESIS TITLE]*. MSc thesis, [UNIVERSITY]. [URL/DOI]

## License

Code released under **[LICENSE NAME]** — see [LICENSE](LICENSE).
Input data in `data/` is subject to its own terms; see `data/README.md`.
