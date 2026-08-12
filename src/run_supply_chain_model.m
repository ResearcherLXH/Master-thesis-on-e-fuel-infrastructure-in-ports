
% Scenario A = 25% methanol, Scenario C = 100% methanol
% Scenario B = 25% ammonia, Scenario D = 100% ammonia

clear all; clc; close all

% =========================================================================
% SECTION 0 — RUN CONFIGURATION
% =========================================================================
% Every switch below changes the run without editing the chain itself.

cfg = struct();

cfg.selected_elec = 2;              % 1 = Alkaline 2 = PEM (baseline) 3 = SOEC, Table B.11
cfg.power_mode    = 'Wind';         % 'Wind' | 'Wind and solar' | 'Solar' | 'Continuous'

% Terminal operating mode for the Section 3.6.2 inventory simulation.
% 'export' — inland deliveries accumulate and discharge in one full vessel
%            packet (Eq. B.19). Used for the reported results.
% 'bunker' — inland deliveries accumulate against a continuous offtake at the
%            demand rate, no packet export.
cfg.terminal_mode = 'export';

% Storage sizing basis for the Option 2 production hub.
% 'import'     — same tanks as Option 1, packet term included.
% 'production' — buffer days only; a production hub has no inbound carrier.
cfg.storage_basis_opt2 = 'import';

% Rail siding construction policy.
% 'fitted'   — siding built to the required train length (Eq. 3.50), capped
%              at L_train_max. This is the policy documented in the thesis.
% 'standard' — siding always built at the full L_train_max.
cfg.siding_policy = 'fitted';

% Sensitivity sweeps (Section 4.7) and curve-fit diagnostics (Appendix B.2).
cfg.run_sensitivity    = true;
cfg.sens_min_swing_pct = 0.5;       % [%] display threshold for tornado rows
cfg.sens_demand_level  = 0.25;      % scenarios A and B
cfg.run_fit_diagnostics = true;
% Path to the hourly generation profile, resolved relative to this script so the
% repository runs unchanged on any machine. See data/README.md.
cfg.wind_data_path = fullfile(fileparts(mfilename('fullpath')), '..', 'data', ...
                              'Calculation MTH.xlsx');
if ~strcmp(cfg.power_mode,'Continuous') && ~isfile(cfg.wind_data_path)
    error(['Generation profile not found at:\n  %s\n' ...
           'See data/README.md, or set cfg.power_mode to ''Continuous'' ' ...
           'to run without it.'], cfg.wind_data_path);
end

% =========================================================================
% SECTION 3.4.1 — GLOBAL INPUTS AND ASSUMPTIONS
% Thesis Section 3.4, parameter tables B.1, B.2, B.4, B.6-B.12
% =========================================================================

% ── Demand baseline
cfg.rho_mgo      = 850;             % [kg/m3] Table 4.1
cfg.mgo_demand_t = 1.7e6;           % [t/yr] Gothenburg baseline, Table 4.1
cfg.buffer_days  = 7;               % [d]   t_buffer, Table B.1
cfg.heel_pct     = 0.05;            % [-]   f_heel, Table B.1
cfg.hours_per_year = 8760;
cfg.days_per_year  = 365;

% Fuel properties, Table B.2.
cfg.LHV_mgo        = 42.7;          % [MJ/kg]
cfg.rho_meth       = 786.3;  cfg.LHV_meth = 19.9;
cfg.rho_amm_refrig = 681.97; cfg.LHV_amm  = 18.6;
cfg.rho_amm_pipe   = 564;           % [kg/m3] 30 barg / 50 C, sizing only

% Vessel packets, Table B.4.
cfg.packet_amm   = 87000;           % [m3] DNV reference VLGC
cfg.packet_meth  = 120000;          % [m3] methanol carrier
cfg.packet_mgo   = 120000;          % [m3]
cfg.packet_scale = 1.0;             % [-] swept in the sensitivity analysis

% ── Modal split and land-side logistics
cfg.percentage_pipe  = 0.7;         % [-]
cfg.percentage_rail  = 0.20;
cfg.percentage_truck = 0.10;
cfg.op_days      = 240;             % [d/yr] 48 operating weeks x 5 weekdays
cfg.n_trains_base = 238;            % [1/yr] DNV baseline frequency
cfg.L_train_max  = 740;             % [m] TEN-T freight length limit
cfg.L_cart       = 20;              % [m] wagon length over couplers
cfg.vol_per_cart = 85;              % [m3] usable wagon volume, 50-110 range
cfg.max_trains_per_platform_day = 2; % [1/d] c_max, loading cycles per siding
cfg.truck_capacity_t = 23.9;        % [t/truck] DNV
cfg.tau_truck    = 75;              % [min] midpoint of the 60-90 range
cfg.t_ops        = 720;             % [min] 12 h window, 06:00-18:00
cfg.bay_sides    = 2;               % [-] loading positions per bay
cfg.siding_factor = 1.2;            % [-] sigma, siding length allowance

% ── Storage
cfg.maxfill_mgo      = 0.95;
cfg.maxfill_methanol = 0.80;
cfg.maxfill_ammonia  = 0.875;       % upper bound of the 0.82-0.875 range
cfg.maxtanksize_mgo      = 100000;
cfg.maxtanksize_methanol = 100000;
cfg.maxtanksize_ammonia  = 60000;   % commercial ceiling, Section 2.3.3
cfg.n_pg_max = 6;                   % [-] max tanks per containment group
cfg.h_bund   = 1.5;                 % [m] bund wall height
cfg.s_bldg_mgo = 76; cfg.s_bldg_meth = 76; cfg.s_bldg_amm = 106; % [m] setbacks, 106 m

% ── Pipelines
cfg.peak_factor  = 5;               % [-] k_peak, Eq. 3.56
cfg.v_amm_pipe   = 1.8;  cfg.v_meth_pipe = 2.0;
cfg.v_h2_pipe    = 20.0; cfg.v_water_pipe = 1.5;
cfg.rho_h2_pipe  = 7.8;  cfg.rho_water = 1000;

% ── Synthesis and capture
cfg.dac_space_m2_per_tCO2yr = 0.1;
cfg.dac_energy_kWh_per_tCO2 = 2639;
cfg.meth_space_m2_per_tph   = 2487; % Kasso, own satellite measurement
cfg.meth_energy_MWh_per_ton = 0.71;
cfg.amm_space_m2_per_tph    = 1593;
cfg.amm_energy_MWh_per_ton  = 0.97;
cfg.asu_energy_MWh_per_ton  = 0.114;
cfg.yield_meth = 1.00; cfg.yield_amm = 1.00; % eta_yield

% ── Electrolysers
cfg.elec_name = {'Rely Clear100+ (Alkaline)','Siemens Elyzer (PEM)','FuelCell Energy (SOEC)'};
cfg.elec_eff    = [51.7, 55.0, 43.8];      % [kWh/kg H2] eta_e
cfg.elec_fp_ratio = [0.509, 0.349, 0.079]; % [m2 per kg/day] s_e

% ── Hydrogen buffer
cfg.min_buf_days = 5;               % [d] t_min,buf
cfg.M_sphere_max = 270;             % [t] per LH2 sphere
cfg.rho_LH2      = 70;              % [kg/m3]
cfg.t_wall       = 2.25;            % [m] radial wall addition
cfg.max_tanks_per_group = 6;
cfg.min_spacing_intra_m = 15.24;    % [m] 50 ft
cfg.min_spacing_inter_m = 30.00;
cfg.S_LH2 = 30.48;                  % [m] OSHA setback, liquefied H2, 100 ft
cfg.S_GH2 = 15.24;                  % [m] OSHA setback, gaseous H2, 50 ft
cfg.lambda_pipe = 12;               % [t/km] GH2 pipeline linear capacity
cfg.D_pipe_H2   = 1.4;              % [m]

% ── Bunkering, berth sizing and hazard radii
cfg.L_bunker = 15; cfg.W_bunker = 10;   % [m] manifold hardware per position
cfg.L_bay    = 30; cfg.W_bay    = 15;   % [m] truck bay
cfg.W_rail_base = 5; cfg.W_rail_wide = 15; % [m] siding corridor widths
cfg.r_haz = [50, 25];               % [m] 1 = ammonia (toxic), 2 = methanol (flammable)
cfg.Q_bkr      = 500;               % [m3/h] sustained transfer rate, one position
cfg.t_win_bkr  = 12;                % [h] daily bunkering window
cfg.f_conn     = 0.25;              % [-] connect/purge/document/disconnect fraction
cfg.k_peak_bkr = 1.5;               % [-] non-uniform arrival allowance
cfg.L_vessel_max = 200;             % [m] LOA of the largest vessel per position
cfg.f_packing = 1.35;

% Derive everything that follows from the inputs above.
cfg = fn_derive(cfg);

fprintf('\n%s\n SECTION 3.4.1 — GLOBAL INPUTS & ENERGY EQUIVALENCE\n%s\n', ...
    repmat('=',1,70), repmat('=',1,70));
fprintf(' MGO baseline volume : %10.0f m3/yr (rho = %d kg/m3)\n', ...
    cfg.annual_mgo, cfg.rho_mgo);
fprintf(' MGO baseline daily mean : %10.0f m3/day\n', cfg.annual_mgo/cfg.days_per_year);
fprintf(' Methanol multiplier (Eq. 3.1): %.4f\n', cfg.mult_methanol);
fprintf(' Ammonia multiplier (Eq. 3.1): %.4f\n', cfg.mult_ammonia);
fprintf(' Electrolyser baseline : %s\n', cfg.elec_name{cfg.selected_elec});
fprintf(' Terminal mode / siding policy: %s / %s\n', cfg.terminal_mode, cfg.siding_policy);
fprintf(' Bund basis / packing factor : %s / %.2f\n', cfg.f_packing);

% =========================================================================
% SECTION 3.6.4a — GENERATION RESOURCE
% Thesis Section 3.6.4, Eqs. 3.67-3.73.
% =========================================================================
wind = fn_load_wind(cfg);

fprintf('\n%s\n SECTION 3.6.4a — %s RESOURCE (shared)\n%s\n', ...
    repmat('=',1,70), upper(cfg.power_mode), repmat('=',1,70));
fprintf(' Installed peak capacity : %.3f GW\n', wind.cap_GW);
fprintf(' Capacity factor : %.3f (%.1f%%)\n', wind.CF, wind.CF*100);
fprintf(' Effective electrolyser CF (r=%.2f): %.3f (%.1f%%)\n', ...
    cfg.r_base, wind.elyz_CF, wind.elyz_CF*100);
fprintf(' Hours above %.0f%% of peak : %d h/yr\n', ...
    cfg.r_base*100, sum(wind.hourly_GW > cfg.r_base*wind.cap_GW));

    dm = [31,28,31,30,31,30,31,31,30,31,30,31];
    month_ticks = cumsum([0, dm(1:11)]) * 24;
    month_lbls  = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};

    % Normalised profile, Eq. 3.67, with a 336 h centred moving average
    % drawn over it to expose the seasonal cycle.
    P_norm_full = (wind.hourly_GW / wind.cap_GW) * 100;
    figure('Name',sprintf('3.6.4 — %s Profile', cfg.power_mode),'Position',[150 200 1000 400]);
    plot(1:cfg.hours_per_year, P_norm_full, 'Color','#EDB120','LineWidth',0.7); hold on;
    plot(1:cfg.hours_per_year, movmean(P_norm_full,24*14), 'Color','#D95319','LineWidth',2);
    ylabel('Generation [% of C_{peak}]');
    title(sprintf('%s Annual Profile — raw + 14-day moving average', cfg.power_mode));
    legend({'Hourly','14-day avg'},'Location','northeast');
    xticks(month_ticks); xticklabels(month_lbls); xlim([1 cfg.hours_per_year]); grid on;

    % Power duration curve (Eq. 3.89) and energy capture curve (Eq. 3.90).
    wind_sorted_pct = (sort(wind.hourly_GW,'descend') / wind.cap_GW) * 100;
    if strcmp(cfg.power_mode,'Continuous'), capture_ratios = 1.00;
    else, capture_ratios = 0.05:0.05:1.00; end
    capture_pct = zeros(size(capture_ratios));
    for i = 1:numel(capture_ratios)
        capture_pct(i) = sum(min(wind.hourly_GW, capture_ratios(i)*wind.cap_GW)) / wind.annual_GWh * 100;
    end

    figure('Name','3.6.4 — Utilisation Analysis','Position',[150 150 1200 500]);
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    sgtitle(sprintf('Generation Utilisation — %s Profile', cfg.power_mode),'FontSize',13,'FontWeight','bold');

    nexttile;
    area(1:cfg.hours_per_year, wind_sorted_pct,'FaceColor','#0072BD','FaceAlpha',0.6,'EdgeColor','none');
    hold on;
    if numel(capture_ratios)>1, yline(cfg.r_base*100,'r--','LineWidth',2); end
    title('Power Duration Curve'); xlabel('Hours sorted');
    ylabel(sprintf('%s [%% C_{peak}]', cfg.gen_name));
    xlim([1 cfg.hours_per_year]); ylim([0 100]); grid on;

    nexttile;
    plot(capture_ratios*100, capture_pct,'-o','Color','#D95319','LineWidth',2,'MarkerFaceColor','#D95319');
    hold on;
    if numel(capture_ratios)>1
        idx_ex = find(round(capture_ratios*100) == round(cfg.r_base*100));
        if ~isempty(idx_ex), plot(cfg.r_base*100, capture_pct(idx_ex),'k*','MarkerSize',10,'LineWidth',2); end
    end
    title('Energy Capture Curve'); xlabel('Electrolyser size [% of C_{peak}]');
    ylabel('Energy captured [%]'); ylim([0 100]); grid on;


% =========================================================================
% SCENARIO LOOP
% One pass of the full chain per demand level. Both fuels are computed
% inside each pass, so the four scenarios come out of two runs.
% =========================================================================

demand_levels = [0.25, 1.00];
runs = cell(1, numel(demand_levels));

for k = 1:numel(demand_levels)
    fd = demand_levels(k);
    do_plots = true;
    fprintf('\n\n%s\n RUNNING DEMAND LEVEL %.0f%% (Scenarios %s)\n%s\n', ...
        repmat('#',1,70), fd*100, ternary(fd<0.5,'A and B','C and D'), repmat('#',1,70));
    runs{k} = fn_run_scenario(cfg, wind, fd, do_plots, false);
end

% ── Map the two runs onto the four scenarios 
% Fuel index convention throughout: 1 = Ammonia, 2 = Methanol.
% Each scenario is a (run, fuel) pair. The accessors below hide that indexing
% so the table rows read as one line per quantity.
SC(1) = struct('label','A', 'desc','25% methanol',  'run',1, 'fuel',2);
SC(2) = struct('label','B', 'desc','25% ammonia',   'run',1, 'fuel',1);
SC(3) = struct('label','C', 'desc','100% methanol', 'run',2, 'fuel',2);
SC(4) = struct('label','D', 'desc','100% ammonia',  'run',2, 'fuel',1);

getc = @(s, field) runs{SC(s).run}.(field){SC(s).fuel};      % cell-valued field
getn = @(s, field) runs{SC(s).run}.(field)(SC(s).fuel);      % numeric field
getm = @(s, field, k) runs{SC(s).run}.(field)(SC(s).fuel,k); % matrix-valued field

% =========================================================================
% CONSOLIDATED SCENARIO SUMMARY
% =========================================================================
W = 78; %structure for the command window
fprintf('\n\n%s\n CONSOLIDATED SCENARIO SUMMARY — ALL FOUR SCENARIOS\n%s\n', ...
    repmat('=',1,W), repmat('=',1,W));
hdr = sprintf(' %-34s %9s %9s %9s %9s', 'Quantity', 'Sc-A', 'Sc-B', 'Sc-C', 'Sc-D');
sub = sprintf(' %-34s %9s %9s %9s %9s', '', 'MeOH 25%', 'NH3 25%', 'MeOH 100%', 'NH3 100%');

% ── Demand and storage — Tables 4.3, 4.5-4.8 ─────────────────────────────
fprintf('\n DEMAND AND STORAGE\n%s\n%s\n%s\n', repmat('-',1,W), hdr, sub);
prow('Annual volume [Mm3/yr]',        arrayfun(@(s) getn(s,'annual_vol')/1e6,    1:4), '%9.3f');
prow('Annual mass [Mt/yr]',           arrayfun(@(s) getn(s,'annual_mass_t')/1e6, 1:4), '%9.3f');
prow('Working volume [1000 m3]',      arrayfun(@(s) getn(s,'v_working')/1e3,     1:4), '%9.1f');
prow('Geometric volume [1000 m3]',    arrayfun(@(s) getn(s,'v_geom_tot')/1e3,    1:4), '%9.1f');
prow('Tanks [-]',                     arrayfun(@(s) getn(s,'n_tanks'),           1:4), '%9.0f');
prow('Tank inner diameter [m]',       arrayfun(@(s) getn(s,'D_in'),              1:4), '%9.1f');
prow('Insulation thickness [m]',      arrayfun(@(s) getn(s,'t_insul'),           1:4), '%9.2f');
prow('Tank outer diameter [m]',       arrayfun(@(s) getn(s,'D_out'),             1:4), '%9.1f');
prow('Tank height [m]',               arrayfun(@(s) getn(s,'H_tank'),            1:4), '%9.1f');
prow('H/D ratio [-]',                 arrayfun(@(s) getn(s,'HD'),                1:4), '%9.3f');
prow('Layer 1 hardware [ha]',         arrayfun(@(s) getn(s,'A1')/1e4,            1:4), '%9.2f');
prow('Layer 2 containment [ha]',      arrayfun(@(s) getn(s,'A2')/1e4,            1:4), '%9.2f');
prow('Layer 3 safety [ha]',           arrayfun(@(s) getn(s,'A3')/1e4,            1:4), '%9.2f');
prow('Sim. working volume [1000 m3]', arrayfun(@(s) getn(s,'sim_max_inv')/1e3,   1:4), '%9.1f');
prow('Sim. vessel calls [1/yr]',      arrayfun(@(s) getn(s,'sim_shipments'),     1:4), '%9.0f');

% ── Land-side logistics — Table 4.11 ─────────────────────────────────────
fprintf('\n LAND-SIDE LOGISTICS\n%s\n%s\n', repmat('-',1,W), hdr);
prow('Truck tanker parcel [m3]',      arrayfun(@(s) getn(s,'truck_parcel'),   1:4), '%9.1f');
prow('Truck trips [1/yr]',            arrayfun(@(s) getn(s,'n_trucks_yr'),    1:4), '%9.0f');
prow('Trucks per operating day [-]',  arrayfun(@(s) getn(s,'trucks_per_day'), 1:4), '%9.1f');
prow('Loading bays [-]',              arrayfun(@(s) getn(s,'N_bays'),         1:4), '%9.0f');
prow('Wagon payload [t]',             arrayfun(@(s) getn(s,'cart_payload_t'), 1:4), '%9.1f');
prow('Volume per train [m3]',         arrayfun(@(s) getn(s,'V_train_m3'),     1:4), '%9.1f');
prow('Rail wagons per train [-]',     arrayfun(@(s) getn(s,'n_carts'),        1:4), '%9.0f');
prow('Block trains [1/yr]',           arrayfun(@(s) getn(s,'n_trains'),       1:4), '%9.0f');
prow('Train arrivals per op-day [-]', arrayfun(@(s) getn(s,'trains_per_day'), 1:4), '%9.2f');
prow('Siding length [m]',             arrayfun(@(s) getn(s,'L_siding'),       1:4), '%9.0f');
prow('Platforms required [-]',        arrayfun(@(s) getn(s,'n_platforms'),    1:4), '%9.0f');
prow('Truck station safety [ha]',     arrayfun(@(s) getn(s,'A_truck_safety')/1e4, 1:4), '%9.2f');
prow('Rail safety zone [ha]',         arrayfun(@(s) getn(s,'A_rail_safety')/1e4, 1:4), '%9.2f');
fprintf(' %-34s', 'Train length capped at 740 m');
for s = 1:4, fprintf(' %9s', ternary(getn(s,'rail_capped')==1,'YES','-')); end
fprintf('\n');

% ── Bunkering interface — Table 4.10, Eqs. 3.40-3.42 ─────────────────────
fprintf('\n BUNKERING INTERFACE (Eq. 3.40, demand-driven)\n%s\n%s\n', repmat('-',1,W), hdr);
prow('Daily bunker offtake [m3/day]', arrayfun(@(s) getn(s,'V_bkr_daily'),      1:4), '%9.0f');
prow('Bunker operations per day [-]', arrayfun(@(s) getn(s,'n_bkr_ops_day'),    1:4), '%9.1f');
prow('Transfer positions [-]',        arrayfun(@(s) getn(s,'N_berth'),          1:4), '%9.0f');
prow('Berth hardware [m2]',           arrayfun(@(s) getn(s,'berth_hard'),       1:4), '%9.0f');
prow('Berth safety [ha]',             arrayfun(@(s) getn(s,'berth_safety')/1e4, 1:4), '%9.2f');
prow('Minimum quay frontage [m]',     arrayfun(@(s) getn(s,'L_quay'),           1:4), '%9.0f');

% ── Upstream chain — Tables 4.4, 4.9, 4.12-4.16 ──────────────────────────
fprintf('\n UPSTREAM CHAIN (production hub)\n%s\n%s\n', repmat('-',1,W), hdr);
% Everything from here down is the production hub: reactants, plants,
% electricity and the hydrogen inventory that feeding them requires.
prow('Fuel production [t/day]',    arrayfun(@(s) getn(s,'kg_daily')/1e3, 1:4), '%9.0f');
prow('Hydrogen demand [t/day]',    arrayfun(@(s) getn(s,'H2_day')/1e3,   1:4), '%9.1f');
prow('CO2 or N2 demand [t/day]',   arrayfun(@(s) getn(s,'CN_day')/1e3,   1:4), '%9.0f');
prow('Water demand [t/day]',       arrayfun(@(s) getn(s,'H2O_day')/1e3,  1:4), '%9.0f');
prow('Oxygen released [t/day]',    arrayfun(@(s) getn(s,'O2_day')/1e3,   1:4), '%9.0f');
prow('Product pipeline [mm]',      arrayfun(@(s) getn(s,'D_prod')*1e3,   1:4), '%9.0f');
prow('Hydrogen pipeline [mm]',     arrayfun(@(s) getn(s,'D_h2')*1e3,     1:4), '%9.0f');
prow('Water supply pipeline [mm]', arrayfun(@(s) getn(s,'D_water')*1e3,  1:4), '%9.0f');
prow('Synthesis plant [ha]',       arrayfun(@(s) getn(s,'synth_ha'),     1:4), '%9.2f');
prow('DAC [ha]',                   arrayfun(@(s) getn(s,'dac_ha'),       1:4), '%9.2f');
prow('Electrolyser [GW]',          arrayfun(@(s) getn(s,'elyz_GW'),      1:4), '%9.2f');
prow('Electrolyser [ha]',          arrayfun(@(s) getn(s,'elec_ha'),      1:4), '%9.2f');
prow('Wind farm [GW]',             arrayfun(@(s) getn(s,'wind_GW'),      1:4), '%9.2f');
prow('H2 buffer [1000 t]',         arrayfun(@(s) getn(s,'buf_kg')/1e6,   1:4), '%9.2f');
prow('H2 buffer [days]',           arrayfun(@(s) getn(s,'buf_days'),     1:4), '%9.1f');
prow('Off-site LRC bulk [1000 t]', arrayfun(@(s) getn(s,'buf_off_kg')/1e6, 1:4), '%9.2f');
prow('On-site H2 mass [t]',        arrayfun(@(s) getn(s,'H2_day')/1e3,   1:4), '%9.0f');
prow('LH2 spheres [-]',            arrayfun(@(s) getn(s,'N_sphere'),     1:4), '%9.0f');
prow('Mass per sphere [t]',        arrayfun(@(s) getn(s,'M_per_sphere')/1e3, 1:4), '%9.0f');
prow('Sphere groups [-]',          arrayfun(@(s) getn(s,'n_sph_groups'), 1:4), '%9.0f');
prow('LH2 sphere safety [ha]',     arrayfun(@(s) getn(s,'sph_A_safety')/1e4, 1:4), '%9.2f');
prow('GH2 pipe option [km]',       arrayfun(@(s) getn(s,'pipe_km'),      1:4), '%9.2f');
prow('GH2 pipe hardware [ha]',     arrayfun(@(s) getn(s,'pipe_hard')/1e4, 1:4), '%9.2f');
prow('GH2 pipe safety [ha]',       arrayfun(@(s) getn(s,'pipe_safety')/1e4, 1:4), '%9.2f');

% ── Hydrogen buffer against the capacity ratio — Table 4.14 ──────────────
fprintf('\n H2 BUFFER AT THE REPORTED CAPACITY RATIOS\n%s\n%s\n', repmat('-',1,W), hdr);
r_rep = runs{1}.buf_r;
for k = 1:numel(r_rep)
    prow(sprintf('r = %.2f  buffer [1000 t]', r_rep(k)), ...
        arrayfun(@(s) getm(s,'buf_r_t',k)/1e3, 1:4), '%9.2f');
    prow(sprintf('r = %.2f  cover [days]', r_rep(k)), ...
        arrayfun(@(s) getm(s,'buf_r_days',k), 1:4), '%9.1f');
end

% ── Option 1, import hub — Table 4.17. Layer 3 areas only ────────────────
fprintf('\n OPTION 1 — IMPORT HUB [ha]\n%s\n%s\n', repmat('-',1,W), hdr);
o1lab = {'Fuel storage (safety)','Ship berths (safety)','Truck station (safety)','Rail spur (safety)'};
for i = 1:4
    prow(o1lab{i}, arrayfun(@(s) subidx(getc(s,'opt1_comp_c'), i), 1:4), '%9.2f');
end
fprintf('%s\n', repmat('-',1,W));
prow('NET total (asset sum)', arrayfun(@(s) getn(s,'opt1_total'), 1:4), '%9.2f');
prow(sprintf('GROSS total (x%.2f)', cfg.f_packing), ...
    arrayfun(@(s) getn(s,'opt1_gross'), 1:4), '%9.2f');

% ── Option 2, production hub — Table 4.18 ────────────────────────────────
% Wind farm and bulk H2 inventory are outside the onshore boundary
% (Section 3.2) and are reported above at their computed scale instead.
fprintf('\n OPTION 2 — PRODUCTION HUB [ha] (wind and bulk H2 off-site)\n%s\n%s\n', repmat('-',1,W), hdr);
o2lab = {'Fuel storage (safety)','Electrolyser','H2 buffer spheres (safety)', ...
    'Synthesis plant','DAC (methanol only)','Ship berths (safety)'};
for i = 1:6
    prow(o2lab{i}, arrayfun(@(s) subidx(getc(s,'opt2_comp_c'), i), 1:4), '%9.2f');
end
fprintf('%s\n', repmat('-',1,W));
prow('NET total (asset sum)', arrayfun(@(s) getn(s,'opt2_total'), 1:4), '%9.2f');
prow(sprintf('GROSS total (x%.2f)', cfg.f_packing), ...
    arrayfun(@(s) getn(s,'opt2_gross'), 1:4), '%9.2f');

% ── Energy scale — Table 4.19 ────────────────────────────────────────────
fprintf('\n ENERGY SCALE\n%s\n%s\n', repmat('-',1,W), hdr);
% Three loads only. Electrolysis dominates; DAC exists on the methanol
% pathway alone; the ASU rides with ammonia synthesis.
prow('Electrolysis [GWh/yr]',    arrayfun(@(s) getn(s,'E_elyz'), 1:4), '%9.0f');
prow('DAC [GWh/yr]',             arrayfun(@(s) getn(s,'E_dac'),  1:4), '%9.0f');
prow('Synthesis + ASU [GWh/yr]', arrayfun(@(s) getn(s,'E_syn'),  1:4), '%9.0f');
fprintf('%s\n', repmat('-',1,W));
prow('TOTAL [TWh/yr]', arrayfun(@(s) getn(s,'E_total')/1e3, 1:4), '%9.2f');

% =========================================================================
% PARAMETER POSITION IN LITERATURE RANGE — Section 3.3.2, Table C.11
% =========================================================================
fn_param_position_table(cfg);

% =========================================================================
% SPATIAL FEASIBILITY AGAINST THE PORT LAND INVENTORY — Section 4.6
% =========================================================================
fn_feasibility(runs, SC);

% =========================================================================
% GROSS-TO-NET PACKING SWEEP — Section 4.7.4, Table C.16
% =========================================================================
fn_packing_sweep(runs, SC, cfg);

% =========================================================================
% CROSS-SCENARIO COMPARISON FIGURES
% =========================================================================
    comp_colors = [
        0.20 0.63 0.17;   % storage
        0.12 0.47 0.71;   % berth
        0.89 0.47 0.13;   % truck
        0.55 0.34 0.29;   % rail
        0.98 0.60 0.60;   % electrolyser
        0.74 0.74 0.74;   % H2 spheres
        0.45 0.17 0.50;   % synthesis
        0.99 0.88 0.10;   % DAC
        ];

    % Option 1 stacked by asset, net asset sum with the gross figure labelled.
    figure('Name','All Scenarios — Option 1 Import Hub','Position',[100 100 950 560]);
    d1 = zeros(4,4);
    for s = 1:4, d1(s,:) = getc(s,'opt1_comp_c'); end
    bh = bar(1:4, d1, 'stacked'); hold on; grid on;
    for c = 1:4, bh(c).FaceColor = comp_colors(c,:); end
    xticks(1:4); xticklabels({'Sc-A MeOH 25%','Sc-B NH_3 25%','Sc-C MeOH 100%','Sc-D NH_3 100%'});
    ylabel('Footprint [ha]');
    title('Option 1 — Import Hub, all scenarios (net asset sum)','FontSize',12,'FontWeight','bold');
    legend(o1lab,'Location','northwest','FontSize',9);
    for s = 1:4
        t = sum(d1(s,:));
        text(s, t*1.02, sprintf('%.1f ha net / %.1f gross', t, t*cfg.f_packing), ...
            'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
    end

    % Option 2 stacked. The two zero columns keep the colour order aligned
    % with Option 1 so the same asset carries the same colour in both figures.
    figure('Name','All Scenarios — Option 2 Production Hub','Position',[130 130 950 560]);
    d2 = zeros(4,6);
    for s = 1:4, d2(s,:) = getc(s,'opt2_comp_c'); end
    d2p = [d2(:,1) d2(:,6) zeros(4,2) d2(:,2) d2(:,3) d2(:,4) d2(:,5)];
    bh2 = bar(1:4, d2p, 'stacked'); hold on; grid on;
    for c = 1:8, bh2(c).FaceColor = comp_colors(c,:); end
    xticks(1:4); xticklabels({'Sc-A MeOH 25%','Sc-B NH_3 25%','Sc-C MeOH 100%','Sc-D NH_3 100%'});
    ylabel('Footprint [ha]');
    title('Option 2 — Production Hub, all scenarios (wind and bulk H_2 off-site)', ...
        'FontSize',12,'FontWeight','bold');
    legend({'Fuel storage','Ship berths','','','Electrolyser','H_2 spheres', ...
        'Synthesis plant','DAC'},'Location','northwest','FontSize',9);
    for s = 1:4
        t = sum(d2p(s,:));
        text(s, t*1.02, sprintf('%.0f ha net / %.0f gross', t, t*cfg.f_packing), ...
            'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
    end

    % Annual electricity demand split by load, Section 4.5.3.
    figure('Name','All Scenarios — Energy Demand','Position',[160 160 950 500]);
    de = zeros(4,3);
    for s = 1:4
        de(s,:) = [getn(s,'E_elyz'), getn(s,'E_dac'), getn(s,'E_syn')]/1e3;
    end
    bh3 = bar(1:4, de, 'stacked'); hold on; grid on;
    bh3(1).FaceColor = [0.98 0.60 0.60];
    bh3(2).FaceColor = [0.99 0.88 0.10];
    bh3(3).FaceColor = [0.45 0.17 0.50];
    xticks(1:4); xticklabels({'Sc-A MeOH 25%','Sc-B NH_3 25%','Sc-C MeOH 100%','Sc-D NH_3 100%'});
    ylabel('Electricity demand [TWh/yr]');
    title('Annual electricity demand by scenario','FontSize',12,'FontWeight','bold');
    legend({'Electrolysis','DAC','Synthesis + ASU'},'Location','northwest','FontSize',9);

    % The six in-group arrangements produced by Eqs. 3.23-3.24, reproduced as
    % Figure 3.3. Unit diameter and unit pitch; shape only, not scale.
    figure('Name','Eqs. 3.23-3.24 — In-Group Arrangements','Position',[100 100 1150 260]);
    tiledlayout(1,6,'TileSpacing','compact','Padding','compact');
    D_ref = 1; cc_ref = 1.5;
    for n_t = 1:6
        [n_row, n_col] = fn_grid(n_t);
        nexttile; hold on; axis equal off;
        Wg = (n_col-1)*cc_ref + D_ref;
        Hg = (n_row-1)*cc_ref + D_ref;
        rectangle('Position',[-D_ref/2, -D_ref/2, Wg, Hg], ...
            'EdgeColor','k','LineStyle',':','LineWidth',1.1);
        for r = 1:n_row
            for c = 1:n_col
                if (r-1)*n_col + c <= n_t
                    rectangle('Position',[(c-1)*cc_ref - D_ref/2, (r-1)*cc_ref - D_ref/2, D_ref, D_ref], ...
                        'Curvature',[1 1],'FaceColor',[0.12 0.47 0.71],'EdgeColor','k');
                end
            end
        end
        title(sprintf('n_t = %d\n%d \\times %d', n_t, n_col, n_row),'FontSize',10);
        xlim([-0.9, max(Wg,3.5)+0.4]); ylim([-0.9, Hg+0.4]);
    end

% =========================================================================
% SENSITIVITY ANALYSIS — Section 3.8, results in Section 4.7
% =========================================================================

if cfg.run_sensitivity
    fn_sensitivity(cfg, wind);
    fn_storage_drivers(cfg, wind);
    fn_distribution_drivers(cfg, wind);
    fn_elyz_ratio_sweep(cfg, wind);
    fn_supply_compare(cfg);
    fn_terminal_mode_compare(cfg, wind);
end

% =========================================================================
% CURVE-FIT DIAGNOSTICS — Appendix B.2
% =========================================================================
if cfg.run_fit_diagnostics
    fn_fit_diagnostics();
end

fprintf('\n%s\n END OF MODEL\n%s\n', repmat('=',1,78), repmat('=',1,78));

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

% -------------------------------------------------------------------------
% DERIVED QUANTITIES AND SMALL HELPERS
% -------------------------------------------------------------------------

function cfg = fn_derive(cfg)
% FN_DERIVE Everything that follows from the primary inputs. Called once at
% start-up and again after every sensitivity perturbation, so no derived
% quantity can go stale behind a swept parameter.

    % Eq. 3.2 reference volume and Eq. 3.1 volumetric multipliers.
    cfg.annual_mgo    = cfg.mgo_demand_t / cfg.rho_mgo * 1000;
    cfg.mult_methanol = (cfg.rho_mgo * cfg.LHV_mgo) / (cfg.rho_meth * cfg.LHV_meth);
    cfg.mult_ammonia  = (cfg.rho_mgo * cfg.LHV_mgo) / (cfg.rho_amm_refrig * cfg.LHV_amm);

    % Baseline electrolyser-to-generation ratio r, Section 3.6.4. A constant
    % supply needs no absorption headroom, so r = 1 there.
    if strcmp(cfg.power_mode,'Continuous'), cfg.r_base = 1.00; else, cfg.r_base = 0.70; end

    switch cfg.power_mode
        case 'Wind';           cfg.gen_name = 'Wind Farm';
        case 'Wind and solar'; cfg.gen_name = 'Hybrid Array';
        case 'Solar';          cfg.gen_name = 'Solar Array';
        case 'Continuous';     cfg.gen_name = 'Baseload Power';
    end

    %Density for transport and storages
    cfg.rho_store = [cfg.rho_amm_refrig, cfg.rho_meth];
    cfg.rho_ship  = [cfg.rho_amm_refrig, cfg.rho_meth];
    cfg.rho_rail  = [602.8, cfg.rho_meth];
    cfg.rho_road  = [602.8, cfg.rho_meth];
    cfg.rho_pipe  = [cfg.rho_amm_pipe, cfg.rho_meth];
end

function prow(label, vals, fmt)
% PROW = Print one row of the consolidated scenario table.
    fprintf(' %-34s', label);
    for i = 1:numel(vals), fprintf([' ' fmt], vals(i)); end
    fprintf('\n');
end

%subidx lets you instantly extract a specific item from an array
function v = subidx(vec, i)
    v = vec(i);
end

%ternary provides a compact, one-line "if-else" statement
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end

% -------------------------------------------------------------------------
% GENERATION PROFILE
% -------------------------------------------------------------------------

function wind = fn_load_wind(cfg)
% FN_LOAD_WIND Load the hourly generation profile and derive the capacity factor CF and
% the effective electrolyser capacity factor at the baseline ratio r.

    if ~strcmp(cfg.power_mode,'Continuous')
        opts = spreadsheetImportOptions("NumVariables",14);
        opts.Sheet = "Blad2";
        opts.DataRange = "A2:N8761";
        vn = ["Var1","Var2","Var3","Var4","Var5","Var6","Var7","Var8", ...
              "Var9","Var10","Var11","Var12","Var13","Var14"];
        opts.VariableNames = vn;
        switch cfg.power_mode
            case 'Wind'
                opts.SelectedVariableNames = ["Var1","Var9","Var12","Var13","Var14"];
                opts.VariableTypes = ["double","char","char","char","char","char","char","char","double","char","char","double","double","double"];
                opts = setvaropts(opts,["Var2","Var3","Var4","Var5","Var6","Var7","Var8","Var10","Var11"],"WhitespaceRule","preserve","EmptyFieldRule","auto");
            case 'Wind and solar'
                opts.SelectedVariableNames = ["Var1","Var10","Var12","Var13","Var14"];
                opts.VariableTypes = ["double","char","char","char","char","char","char","char","char","double","char","double","double","double"];
                opts = setvaropts(opts,["Var2","Var3","Var4","Var5","Var6","Var7","Var8","Var9","Var11"],"WhitespaceRule","preserve","EmptyFieldRule","auto");
            case 'Solar'
                opts.SelectedVariableNames = ["Var1","Var7","Var12","Var13","Var14"];
                opts.VariableTypes = ["double","char","char","char","char","char","double","char","char","char","char","double","double","double"];
                opts = setvaropts(opts,["Var2","Var3","Var4","Var5","Var6","Var8","Var9","Var10","Var11"],"WhitespaceRule","preserve","EmptyFieldRule","auto");
        end
        
        raw = readtable(cfg.wind_data_path, opts, "UseExcel", false);
        hourly_GW = raw{1:cfg.hours_per_year,2} / 1e3;
    else
        hourly_GW = ones(cfg.hours_per_year,1);
    end

    wind.hourly_GW  = hourly_GW;
    wind.cap_GW     = max(hourly_GW);              % C_peak, Eq. 3.68
    wind.annual_GWh = sum(hourly_GW);              % E_annual, Eq. 3.69
    wind.CF         = wind.annual_GWh / (wind.cap_GW * cfg.hours_per_year); % Eq. 3.70
    lim_GW = cfg.r_base * wind.cap_GW;             % P_limit(r), Eq. 3.71
    pct_usable = sum(min(hourly_GW, lim_GW)) / wind.annual_GWh;
    wind.elyz_CF = (pct_usable * wind.CF) / cfg.r_base;
end

function R = fn_run_scenario(cfg, wind, fd, do_plots, quiet)

   % Defines 'pf' as a dynamic print command to easily suppress console output 
   % without altering the main code path.
    if nargin < 5, quiet = false; end
    if quiet, pf = @(varargin) []; else, pf = @fprintf; end

    hpy = cfg.hours_per_year;
    dpy = cfg.days_per_year;
    e   = cfg.selected_elec;
    lvl = sprintf('%.0f%%', fd*100);

    % Eq. 3.2: annual volume of each fuel at this mix fraction.
    annual_mgo      = cfg.annual_mgo;
    annual_methanol = annual_mgo * cfg.mult_methanol * fd;
    annual_ammonia  = annual_mgo * cfg.mult_ammonia  * fd;

    fuel_name  = {'Ammonia','Methanol'};
    annual_vol = [annual_ammonia, annual_methanol];
    packet     = [cfg.packet_amm, cfg.packet_meth] * cfg.packet_scale;
    maxfill    = [cfg.maxfill_ammonia, cfg.maxfill_methanol];
    maxtank    = [cfg.maxtanksize_ammonia, cfg.maxtanksize_methanol];
    s_bldg     = [cfg.s_bldg_amm, cfg.s_bldg_meth];
    r_haz      = cfg.r_haz;
    tank_color = [0.12 0.47 0.71; 0.18 0.63 0.18];
    nf = 2;

    % Pre-allocate every reported quantity so the struct layout is fixed.
    [R.annual_vol, R.annual_mass_t, R.v_working, R.v_geom_tot, R.n_tanks, ...
     R.D_out, R.H_tank, R.A1, R.A2, R.A3, R.sim_max_inv, R.sim_shipments, ...
     R.truck_parcel, R.n_trucks_yr, R.trucks_per_day, R.N_bays, R.n_carts, ...
     R.n_trains, R.trains_per_day, R.L_siding, R.n_platforms, R.A_rail_safety, ...
     R.cart_payload_t, R.rail_capped, R.V_bkr_daily, R.n_bkr_ops_day, ...
     R.N_berth, R.berth_hard, R.berth_safety, R.kg_daily, R.H2_day, R.CN_day, ...
     R.H2O_day, R.O2_day, R.D_prod, R.D_h2, R.synth_ha, R.dac_ha, R.elyz_GW, ...
     R.elec_ha, R.wind_GW, R.buf_kg, R.buf_days, ...
     R.N_sphere, R.sph_A_safety, R.opt1_total, R.opt2_total, R.opt1_gross, ...
     R.opt2_gross, R.E_elyz, R.E_dac, R.E_syn, R.E_total, R.D_in, R.t_insul, ...
     R.HD, R.D_water, R.L_quay, R.A_truck_safety, R.V_train_m3, R.buf_off_kg, ...
     R.M_per_sphere, R.n_sph_groups, R.pipe_km, R.pipe_hard, R.pipe_safety] ...
        = deal(zeros(1,nf));
    R.opt1_comp_c = cell(1,nf);
    R.opt2_comp_c = cell(1,nf);
    R.buf_r      = [0.40 0.70 1.00];   % ratios reported in Table 4.14
    R.buf_r_t    = zeros(nf,3);        % buffer mass [t] at those ratios
    R.buf_r_days = zeros(nf,3);        % and the demand cover in days

    % =====================================================================
    % SECTION 3.6.1 — STORAGE
    % Eqs. 3.11-3.21 (sizing) and 3.22-3.37 (layers)
    % =====================================================================
    pf('\n%s\n SECTION 3.6.1 — FUEL STORAGE (%s demand)\n%s\n', ...
        repmat('=',1,70), lvl, repmat('=',1,70));

    A3_o2_v = zeros(1,nf);   % Option 2 storage area, per fuel

    for f = 1:nf
        % Eqs. 3.11-3.16: working volume, effective fraction, tank count.
        eff = maxfill(f) - cfg.heel_pct;
        v_working = (annual_vol(f)/dpy)*cfg.buffer_days + packet(f);
        [n_tanks, ~, V_geom] = fn_tank_split(v_working, eff, maxtank(f));
        V_farm = n_tanks * V_geom;

        if f == 1
            % Ammonia: flat-bottom refrigerated DWDI.
            % Eq. 3.18 H/D fit, Eq. 3.19 inner diameter, Eq. 3.20 insulation
            % thickness, Eq. 3.21 outer envelope.
            ratio  = 0.7012 * exp(-1.48e-06 * V_geom);
            D_in   = (4*V_geom/(pi*ratio))^(1/3);
            H      = ratio * D_in;
            t_ann  = 6.197134e-06 * V_geom + 0.7127;
            D_out  = D_in + 2*t_ann;
            d_shell = max(30, D_out);       % delta_shell,amm, Table B.6
            is_dwdi = 1;                    % Layer 2 = Layer 1 by construction
        else
            % Methanol: single-wall fixed roof, Eq. 3.17 and Eq. 3.19.
            ratio  = 0.7661 * exp(-1.18e-05 * V_geom);
            D_in   = (4*V_geom/(pi*ratio))^(1/3);
            H      = ratio * D_in;
            D_out  = D_in;                  % single wall
            t_ann  = 0;                     % no annular insulation
            d_shell = max(30, 0.5*D_out);   % delta_shell, Table B.6, 30 m floor
            is_dwdi = 0;
        end
        % Spacing between containment groups, floored at 30 m.
        d_btw = max(30, D_out);             % delta_btw, Eq. 3.28

        % Eqs. 3.22-3.37: the three-layer envelope.
        [A1,W1,H1, A2,W2,H2, A3,W3,H3] = fn_three_layer(n_tanks, V_geom, V_farm, ...
            D_out, d_shell, d_btw, s_bldg(f), is_dwdi, cfg.n_pg_max, cfg.h_bund);

        % Optional production-hub storage basis: a hub that makes its own fuel
        % and continous output dont need the packet term of Eq. 3.11.
        % The tank farm is re-sized on the buffer alone.
        if strcmp(cfg.storage_basis_opt2,'production')
            % Same geometry, re-solved on the smaller duty. Only the Layer 3
            % area is kept, since that is what the aggregation uses.
            v_w_o2 = (annual_vol(f)/dpy)*cfg.buffer_days;
            [nt2, ~, Vg2] = fn_tank_split(v_w_o2, eff, maxtank(f));
            if f == 1
                rr = 0.7012*exp(-1.48e-06*Vg2); Di2 = (4*Vg2/(pi*rr))^(1/3);
                Do2 = Di2 + 2*(6.197134e-06*Vg2 + 0.7127); ds2 = max(30,Do2);
            else
                rr = 0.7661*exp(-1.18e-05*Vg2); Di2 = (4*Vg2/(pi*rr))^(1/3);
                Do2 = Di2; ds2 = max(30,0.5*Do2);
            end
            [~,~,~,~,~,~, A3_o2, ~,~] = fn_three_layer(nt2, Vg2, nt2*Vg2, Do2, ds2, ...
                max(30,Do2), s_bldg(f), is_dwdi, cfg.n_pg_max, cfg.h_bund);
        else
            A3_o2 = A3;
        end

        R.annual_vol(f)    = annual_vol(f);
        R.annual_mass_t(f) = annual_vol(f) * cfg.rho_store(f) / 1000;
        R.v_working(f)     = v_working;
        R.v_geom_tot(f)    = v_working/eff;
        R.n_tanks(f)       = n_tanks;
        R.D_out(f)         = D_out;
        R.D_in(f)          = D_in;
        R.t_insul(f)       = t_ann;
        R.H_tank(f)        = H;
        R.HD(f)            = H/D_in;
        R.A1(f) = A1; R.A2(f) = A2; R.A3(f) = A3;

        A3_o2_v(f) = A3_o2;

        pf('\n [%s] %d tanks\n', fuel_name{f}, n_tanks);
        pf(' V_work = %9.0f m3 V_geom/tank = %8.0f m3\n', v_working, V_geom);
        pf(' D_in = %.1f m D_out = %.1f m H = %.1f m (H/D = %.2f, t_insul = %.2f m)\n', ...
            D_in, D_out, H, H/D_in, t_ann);
        pf(' Layer 1 %8.0f m2 (%6.1f x %6.1f)\n', A1, W1, H1);
        pf(' Layer 2 %8.0f m2 (%6.1f x %6.1f)\n', A2, W2, H2);
        pf(' Layer 3 %8.0f m2 (%6.1f x %6.1f, s=%.0f m)\n', A3, W3, H3, s_bldg(f));

        if do_plots
            fn_plot_tank_layout(fuel_name{f}, lvl, n_tanks, D_out, D_in, ...
                d_shell(1), d_btw, is_dwdi, cfg.n_pg_max, ...
                W1,H1, W2,H2, W3,H3, tank_color(f,:));
        end
    end

    % =====================================================================
    % SECTION 3.6.2a — RAIL CONFIGURATION
    % Eqs. 3.47-3.52. 
    % =====================================================================
    rail = cell(1,nf);
    for f = 1:nf
        mass_rail_kg = cfg.percentage_rail * annual_vol(f) * cfg.rho_store(f);
        rail{f} = fn_rail_config(mass_rail_kg, cfg.n_trains_base, ...
            cfg.vol_per_cart, cfg.rho_rail(f), cfg.L_cart, cfg.L_train_max, ...
            cfg.siding_policy, cfg.siding_factor, cfg.op_days, ...
            cfg.max_trains_per_platform_day);
    end

    % =====================================================================
    % SECTION 3.6.2 — TERMINAL SIMULATION
    % Eqs. B.12-B.19. 
    % =====================================================================
    pf('\n%s\n SECTION 3.6.2 — TERMINAL SIMULATION (%s demand, mode: %s)\n%s\n', ...
        repmat('=',1,70), lvl, cfg.terminal_mode, repmat('=',1,70));

    for f = 1:nf
        Rc = rail{f};

        
        Pipe_In_h    = cfg.percentage_pipe * annual_vol(f) / hpy;
        mass_road_kg = cfg.percentage_truck * annual_vol(f) * cfg.rho_store(f);
        tr_vol_hr    = (mass_road_kg / cfg.op_days / cfg.rho_store(f)) / 12;
        V_train_store = Rc.mass_per_train / cfg.rho_store(f);
        trains_pd    = Rc.n_trains / cfg.op_days;
        bunk_out_h   = annual_vol(f) / hpy;

        % Hour-by-hour inventory balance over one year. cur is the running
        % stock, credit the fractional train awaiting a whole arrival.
        inv = zeros(1,hpy); cur = 0; credit = 0; ships = 0; trains_rx = 0;

        for h = 1:hpy
            % Continuous pipeline inflow, every hour of the year.
            cur = cur + Pipe_In_h;

            doy = ceil(h/24);
            dow = mod(doy-1,7)+1;
            hod = mod(h-1,24)+1;
            % Operating calendar D_op: weekdays of the first 48 weeks.
            is_op = (dow <= 5) && (doy <= 48*7);

            if is_op
                % Rail impulse at noon. Train frequency is not an
                % integer per day, so arrivals accumulate as a fractional
                % credit and discharge whenever a whole train is due.
                if hod == 12
                    credit = credit + trains_pd;
                    nt = floor(credit); credit = credit - nt;
                    cur = cur + nt*V_train_store;
                    trains_rx = trains_rx + nt;
                end
                % Truck deliveries spread over the 12 daytime slots
                if hod >= 6 && hod <= 17
                    cur = cur + tr_vol_hr;
                end
            end

            switch cfg.terminal_mode
                case 'export'   % Eq. B.19, one full packet leaves on reaching V_pkt
                    if cur >= packet(f)
                        cur = cur - packet(f); ships = ships + 1;
                    end
                case 'bunker'   % continuous offtake at the demand rate
                    cur = cur - bunk_out_h;
            end
            inv(h) = cur;
        end

        % Shift the trajectory so its minimum sits on the safety buffer, then
        % read the working volume off the peak.
        min_buf = (annual_vol(f)/dpy)*cfg.buffer_days;
        inv = inv + (min_buf - min(inv));
        max_inv = max(inv);
        nominal = max_inv / (maxfill(f) - cfg.heel_pct);   % gross tank volume

        R.sim_max_inv(f)   = max_inv;
        R.sim_shipments(f) = ships;

        pf(' [%s] pipeline %.2f m3/hr trains received %d (%.2f/op-day) vessel calls %d\n', ...
            fuel_name{f}, Pipe_In_h, trains_rx, trains_pd, ships);
        pf(' buffer %9.0f working %9.0f nominal %9.0f m3\n', ...
            min_buf, max_inv, nominal);

        if do_plots
            fn_plot_inventory(fuel_name{f}, lvl, inv, min_buf, max_inv, ...
                nominal, ships, packet(f), cfg);
        end
    end

    % =====================================================================
    % SECTIONS 3.5.1, 3.6.2, 3.6.3 — REACTANTS, PIPELINES, SYNTHESIS
    % (Eqs. 3.3-3.10), (Eqs. 3.55-3.59) and
    %(Eqs. 3.60-3.66)
    % =====================================================================
    pf('\n%s\n SECTIONS 3.5.1/3.6.2/3.6.3 — REACTANTS, PIPELINES, SYNTHESIS (%s)\n%s\n', ...
        repmat('=',1,70), lvl, repmat('=',1,70));

    % Eqs. 3.55-3.59 in one expression: daily mass to peak mass flow, to
    % volumetric flow at the carried density, to diameter at the design velocity.
    pipe_D = @(m_kgd, rho_fl, v_fl) ...
        sqrt((4*(m_kgd/(24*3600)*cfg.peak_factor/rho_fl)/v_fl)/pi);

    for f = 1:nf
        kg_daily = (annual_vol(f)/dpy) * cfg.rho_store(f); % Eq. 3.9

        if f == 1
            % Ammonia, N2 + 3H2 -> 2NH3. Eqs. 3.5-3.6 stoichiometric ratios,
            % divided by the yield factor of Eq. 3.10.
            H2_day   = kg_daily * ((3/2*2)/17) / cfg.yield_amm;
            CN_day   = kg_daily * ((1/2*28)/17) / cfg.yield_amm;
            D_prod   = pipe_D(kg_daily, cfg.rho_pipe(1), cfg.v_amm_pipe);
            synth_ha = cfg.amm_space_m2_per_tph * (kg_daily/(24*1000)) / 1e4;   % Eq. 3.64
            synth_MW = cfg.amm_energy_MWh_per_ton * (kg_daily/1000) / 24;       % Eq. 3.65
            asu_MW   = cfg.asu_energy_MWh_per_ton * (kg_daily/1000) / 24;       % Eq. 3.66
            dac_ha = 0; dac_GW = 0;
            E_syn  = (synth_MW + asu_MW) * hpy / 1e3;
        else
            % Methanol, CO2 + 3H2 -> CH3OH + H2O. Eqs. 3.3-3.4.
            H2_day   = kg_daily * ((3*2)/32) / cfg.yield_meth;
            CN_day   = kg_daily * ((1*44)/32) / cfg.yield_meth;
            D_prod   = pipe_D(kg_daily, cfg.rho_pipe(2), cfg.v_meth_pipe);
            synth_ha = cfg.meth_space_m2_per_tph * (kg_daily/(24*1000)) / 1e4;  % Eq. 3.62
            synth_MW = cfg.meth_energy_MWh_per_ton * (kg_daily/1000) / 24;      % Eq. 3.63
            % DAC is sized on an annual CO2 basis, Eqs. 3.60-3.61.
            dac_tCO2_yr = CN_day * dpy / 1000;
            dac_ha = dac_tCO2_yr * cfg.dac_space_m2_per_tCO2yr / 1e4;
            dac_GW = (CN_day/1000) * cfg.dac_energy_kWh_per_tCO2 / (24*1e6);
            E_syn  = synth_MW * hpy / 1e3;
        end
        D_h2 = pipe_D(H2_day, cfg.rho_h2_pipe, cfg.v_h2_pipe);

        % Eqs. 3.7-3.8 give the water and oxygen streams.
        H2O_day = H2_day*9;
        D_water = pipe_D(H2O_day, cfg.rho_water, cfg.v_water_pipe);

        R.kg_daily(f) = kg_daily;
        R.H2_day(f)   = H2_day;
        R.CN_day(f)   = CN_day;
        R.H2O_day(f)  = H2O_day;     % Eq. 3.7, r_H2O,H2
        R.O2_day(f)   = H2_day*8;    % Eq. 3.8, r_O2,H2
        R.D_prod(f)   = D_prod;
        R.D_h2(f)     = D_h2;
        R.D_water(f)  = D_water;
        R.synth_ha(f) = synth_ha;
        R.dac_ha(f)   = dac_ha;
        R.E_dac(f)    = dac_GW * 1e3 * hpy / 1e3;
        R.E_syn(f)    = E_syn;

        pf(' [%s] %7.0f t/day H2 %7.1f t/day reactant %7.0f t/day\n', ...
            fuel_name{f}, kg_daily/1e3, H2_day/1e3, CN_day/1e3);
        pf(' product pipe %4.0f mm H2 pipe %4.0f mm water pipe %4.0f mm synthesis %6.2f ha', ...
            D_prod*1e3, D_h2*1e3, D_water*1e3, synth_ha);
        if f == 2, pf(' DAC %6.2f ha', dac_ha); end
        pf('\n');
    end

    % =====================================================================
    % SECTION 3.6.4 — ELECTROLYSER SIZING
    % Eqs. 3.74-3.78.
    % =====================================================================
    pf('\n%s\n SECTION 3.6.4 — ELECTROLYSER SIZING (%s)\n%s\n', ...
        repmat('=',1,70), lvl, repmat('=',1,70));

    for f = 1:nf
        E_req_GWh = R.H2_day(f) * cfg.elec_eff(e) * dpy / 1e6;      % Eq. 3.74
        peak_elyz = E_req_GWh / (wind.elyz_CF * hpy); %Eq. 3.76 & Eq. 3.75
        R.elyz_GW(f) = peak_elyz;
        R.wind_GW(f) = peak_elyz / cfg.r_base;                      % Eq. 3.75

        pk_H2 = (peak_elyz*24*1e6) / cfg.elec_eff(e);               %Eq. 3.77
        R.elec_ha(f) = pk_H2 * cfg.elec_fp_ratio(e) / 1e4;          %Eq. 3.78, but in Ha instead of m^3
        R.E_elyz(f)  = E_req_GWh;

        pf(' [%s] %s %6.2f GW (~%5.0f km2 offshore) | electrolyser %5.2f GW / %6.2f ha | %8.0f GWh/yr\n', ...
            fuel_name{f}, cfg.gen_name, R.wind_GW(f), peak_elyz, R.elec_ha(f), E_req_GWh);
    end

    % =====================================================================
    % SECTION 3.6.4 — HYDROGEN BUFFER
    % Thesis Section 3.6.4, Eqs. 3.80-3.88
    % =====================================================================
    pf('\n%s\n SECTION 3.6.4 — HYDROGEN BUFFER (%s)\n%s\n', ...
        repmat('=',1,70), lvl, repmat('=',1,70));

    if strcmp(cfg.power_mode,'Continuous'), cap_pct = 100;
    else, cap_pct = [70, 100, 80, 60, 40, 20]; end
    n_scen = numel(cap_pct);

    for f = 1:nf
        daily_H2 = R.H2_day(f);
        buf_kg   = daily_H2 * cfg.min_buf_days;     % V_buf, Eq. 3.84
        S_prof = cell(1,n_scen);
        tk_kg  = zeros(1,n_scen);

        for s = 1:n_scen
            r = cap_pct(s)/100;
            f_use = sum(min(wind.hourly_GW, r*wind.cap_GW)) / wind.annual_GWh;
            E_req = daily_H2 * cfg.elec_eff(e) * dpy / 1e6;
            w_GW  = E_req / (wind.CF * f_use * hpy);
            e_GW  = w_GW * r;

            hw_sc = wind.hourly_GW * (w_GW / wind.cap_GW);  % Eq. 3.80:
            dprod = zeros(dpy,1);
            for d = 1:dpy
                dprod(d) = sum(min(hw_sc((d-1)*24+1:d*24), e_GW))*1e6 / cfg.elec_eff(e);
            end

            % Eqs. 3.81-3.85: 
            cn = cumsum(dprod - daily_H2);
            S  = cn - min(cn) + buf_kg;
            S_prof{s} = S; tk_kg(s) = max(S);
        end

        R.buf_kg(f)   = tk_kg(1);
        R.buf_days(f) = tk_kg(1) / daily_H2;

        % Buffer requirement at the three ratios reported in Table 4.14.
        for k = 1:numel(R.buf_r)
            idx = find(abs(cap_pct/100 - R.buf_r(k)) < 1e-9, 1);
            if ~isempty(idx)
                R.buf_r_t(f,k)    = tk_kg(idx)/1e3;
                R.buf_r_days(f,k) = tk_kg(idx)/daily_H2;
            end
        end

        
        M_on   = daily_H2;      % Eq. 3.86:
        N_sph  = ceil(M_on / (cfg.M_sphere_max*1000));
        M_sph  = cfg.M_sphere_max*1000;
        V_sph  = M_sph / cfg.rho_LH2;
        D_in_s = 2*((3*V_sph)/(4*pi))^(1/3);
        D_out_s= D_in_s + 2*cfg.t_wall;
        d_intra= max(D_out_s, cfg.min_spacing_intra_m);
        d_inter= max(D_out_s, cfg.min_spacing_inter_m);

        grps = fn_group_split(N_sph, cfg.max_tanks_per_group);
        Wp = 0; Lp = 0;
        for i = 1:numel(grps)
            [nr, nc] = fn_grid(grps(i));
            Wp = Wp + nc*D_out_s + max(0,nc-1)*d_intra;
            Lp = max(Lp, nr*D_out_s + max(0,nr-1)*d_intra);
        end
        if numel(grps) > 1, Wp = Wp + (numel(grps)-1)*d_inter; end
        A_safe_sph = (Wp + 2*cfg.S_LH2) * (Lp + 2*cfg.S_LH2);   % Eq. 3.87

        % Local Option B, Eqs. B.11 and 3.68: the same one-day mass held in
        % large-diameter pipe instead of spheres. Reported for the comparison
        % only; the spheres are what enters the aggregated totals.
        L_pipe_km  = (M_on/1000) / cfg.lambda_pipe;
        A_pipe_hd  = (L_pipe_km*1000) * cfg.D_pipe_H2;
        A_pipe_sf  = (L_pipe_km*1000 + 2*cfg.S_GH2) * (cfg.D_pipe_H2 + 2*cfg.S_GH2);

        R.N_sphere(f)     = N_sph;
        R.sph_A_safety(f) = A_safe_sph;
        R.M_per_sphere(f) = M_on / N_sph;
        R.n_sph_groups(f) = numel(grps);
        R.buf_off_kg(f)   = tk_kg(1) - M_on;
        R.pipe_km(f)      = L_pipe_km;
        R.pipe_hard(f)    = A_pipe_hd;
        R.pipe_safety(f)  = A_pipe_sf;

        pf(' [%s] buffer %7.0f t (%.1f days, ~%.2f Mm3 LRC) on-site %5.0f t in %d sphere(s)\n', ...
            fuel_name{f}, tk_kg(1)/1e3, R.buf_days(f), M_on/1e3, N_sph);
        pf(' sphere D_out %.1f m pad %.0f x %.0f m safety %6.0f m2 (%.2f ha)\n', ...
            D_out_s, Wp, Lp, A_safe_sph, A_safe_sph/1e4);
        pf(' pipe option %.2f km hardware %.2f ha safety %.2f ha\n', ...
            L_pipe_km, A_pipe_hd/1e4, A_pipe_sf/1e4);
        pf(' buffer at r = ');
        pf('%.2f: %6.0f t (%.1f d)  ', [R.buf_r; R.buf_r_t(f,:); R.buf_r_days(f,:)]);
        pf('\n');

        if do_plots
            fn_plot_h2_buffer(fuel_name{f}, lvl, S_prof, tk_kg, cap_pct, ...
                daily_H2, buf_kg, cfg);
            fn_plot_spheres(fuel_name{f}, lvl, grps, D_out_s, d_intra, d_inter, Lp);
        end
    end

    % =====================================================================
    % SECTION 3.6.4 — TRADE-OFF SWEEP (Eq. 3.79)
    % =====================================================================
    if do_plots && ~strcmp(cfg.power_mode,'Continuous')
        fn_plot_tradeoff(cfg, wind, R.H2_day, fuel_name, lvl);
    end

    % =====================================================================
    % SECTIONS 3.6.2 AND 3.6.5 — BUNKERING, TRANSFER, FOOTPRINT ASSEMBLY
    %  Eqs. 3.40-3.46, 3.53-3.54
    % =====================================================================
    pf('\n%s\n SECTION 3.6.2 — BUNKERING AND TRANSFER (%s)\n%s\n', ...
        repmat('=',1,70), lvl, repmat('=',1,70));

    for f = 1:nf
        Rc = rail{f};
        Rh = r_haz(f);

    % ── Bunkering interface
        V_daily = annual_vol(f) / dpy;
        cap_berth_day = cfg.Q_bkr * cfg.t_win_bkr * (1 - cfg.f_conn);   % m3/berth/day
        N_berth = max(1, ceil(cfg.k_peak_bkr * V_daily / cap_berth_day));
        L_quay  = N_berth * (cfg.L_vessel_max + 2*Rh);                  % Eq. 3.43
        A_bkr_hard = N_berth * cfg.L_bunker * cfg.W_bunker;             % Eq. 3.41
        A_bkr_safe = N_berth * (cfg.L_bunker + Rh*2) * (cfg.W_bunker + Rh*2); % Eq. 3.42

        R.V_bkr_daily(f)   = V_daily;
        
        R.n_bkr_ops_day(f) = cfg.k_peak_bkr * V_daily / cap_berth_day;
        R.L_quay(f)        = L_quay;
        R.N_berth(f)       = N_berth;
        R.berth_hard(f)    = A_bkr_hard;
        R.berth_safety(f)  = A_bkr_safe;

        % ── Road reception
        trucks_per_bay_day = floor(cfg.t_ops / cfg.tau_truck) * cfg.bay_sides;
        mass_road_kg = cfg.percentage_truck * annual_vol(f) * cfg.rho_store(f);
        n_tr_yr   = mass_road_kg / (cfg.truck_capacity_t*1000);   % Eq. B.15
        tp_parcel = cfg.truck_capacity_t*1000 / cfg.rho_road(f);  % Eq. 3.39, carried state
        tr_per_day = n_tr_yr / cfg.op_days;
        N_bays    = ceil(tr_per_day / trucks_per_bay_day);
        L_station = N_bays * cfg.L_bay;
        A_tr_hard = L_station * cfg.W_bay;
        if A_tr_hard == 0
            A_tr_safe = 0;
        else
            A_tr_safe = (L_station + Rh*2) * (cfg.W_bay + Rh*2);
        end

        % ── Rail reception
        Lw = Rc.L_siding; Lt = Rc.L_total;
        A_rl_hard = (Lt - Lw)*cfg.W_rail_base + Lw*cfg.W_rail_wide;
        if A_rl_hard == 0
            A_rl_safe = 0;
        else
            A_rl_safe = max(0, Lt - (Lw + Rh*2))*cfg.W_rail_base ...
                + (Lw + Rh*2)*(cfg.W_rail_wide + Rh*2);
        end
        A_rl_hard = A_rl_hard * Rc.n_platforms;
        A_rl_safe = A_rl_safe * Rc.n_platforms;

        R.truck_parcel(f)   = tp_parcel;
        R.A_truck_safety(f) = A_tr_safe;
        R.V_train_m3(f)     = Rc.mass_per_train / cfg.rho_store(f);
        R.n_trucks_yr(f)    = n_tr_yr;
        R.trucks_per_day(f) = tr_per_day;
        R.N_bays(f)         = N_bays;
        R.n_carts(f)        = Rc.n_carts;
        R.cart_payload_t(f) = Rc.cart_payload_t;
        R.n_trains(f)       = Rc.n_trains;
        R.trains_per_day(f) = Rc.trains_per_day;
        R.L_siding(f)       = Rc.L_siding;
        R.n_platforms(f)    = Rc.n_platforms;
        R.A_rail_safety(f)  = A_rl_safe;
        R.rail_capped(f)    = double(Rc.capped);

        pf(' [%s] %d transfer position(s), %.1f bunker ops/day, hardware %5.0f m2, safety %6.0f m2 (R=%d m)\n', ...
            fuel_name{f}, N_berth, R.n_bkr_ops_day(f), A_bkr_hard, A_bkr_safe, Rh);
        pf(' minimum quay frontage %.0f m\n', L_quay);
        pf(' trucks %6.0f/yr (%.1f/day, %.1f m3 each) -> %d bay(s), safety %6.0f m2\n', ...
            n_tr_yr, tr_per_day, tp_parcel, N_bays, A_tr_safe);
        pf(' rail %d wagons @ %.1f t, %d trains/yr (%.2f/op-day), siding %.0f m %s\n', ...
            Rc.n_carts, Rc.cart_payload_t, Rc.n_trains, Rc.trains_per_day, Lw, ...
            ternary(Rc.capped,'[CAPPED]',''));
        pf(' platforms %d, rail safety %6.0f m2 (%.2f ha)\n', ...
            Rc.n_platforms, A_rl_safe, A_rl_safe/1e4);

        % ── Footprint assembly, Section 3.6.5
        %Option 1 is the import hub; Option 2 keeps the storage and the berths and adds the
        % production chain on top.
        o1 = [R.A3(f)/1e4, A_bkr_safe/1e4, A_tr_safe/1e4, A_rl_safe/1e4];
        o2 = [A3_o2_v(f)/1e4, R.elec_ha(f), R.sph_A_safety(f)/1e4, ...
              R.synth_ha(f), R.dac_ha(f), A_bkr_safe/1e4];
        R.opt1_comp_c{f} = o1;
        R.opt2_comp_c{f} = o2;
        R.opt1_total(f)  = sum(o1);
        R.opt2_total(f)  = sum(o2);
        R.opt1_gross(f)  = sum(o1) * cfg.f_packing;
        R.opt2_gross(f)  = sum(o2) * cfg.f_packing;
        R.E_total(f)     = R.E_elyz(f) + R.E_dac(f) + R.E_syn(f);
    end

    pf('\n OPTION 1 net/gross : ammonia %7.2f / %7.2f ha methanol %7.2f / %7.2f ha\n', ...
        R.opt1_total(1), R.opt1_gross(1), R.opt1_total(2), R.opt1_gross(2));
    pf(' OPTION 2 net/gross : ammonia %7.2f / %7.2f ha methanol %7.2f / %7.2f ha\n', ...
        R.opt2_total(1), R.opt2_gross(1), R.opt2_total(2), R.opt2_gross(2));
    pf(' Energy total : ammonia %7.2f TWh methanol %7.2f TWh\n', ...
        R.E_total(1)/1e3, R.E_total(2)/1e3);

    if do_plots
        fn_plot_site_plans(R, lvl);
    end
end

% -------------------------------------------------------------------------
% SENSITIVITY — Section 4.7
% -------------------------------------------------------------------------

function fn_sensitivity(cfg0, wind)
% One-at-a-time sweep of the production-hub parameters. Each
% value is set, the config is re-derived and the identical chain is re-run, so
% a swept result and the baseline result come out of the same code path.

    fd = cfg0.sens_demand_level;
    if ~isfield(cfg0,'sens_min_swing_pct'), cfg0.sens_min_swing_pct = 0.5; end
    W = 96;

    fprintf('\n\n%s\n SECTION 4.7 — SENSITIVITY ANALYSIS (demand level %.0f%%)\n%s\n', ...
        repmat('=',1,W), fd*100, repmat('=',1,W));

    % Baseline first, so every swing below is measured against a result from
    % the same code path rather than against a quoted figure.
    base = fn_run_scenario(cfg0, wind, fd, false, true);
    sA = ternary(fd<0.5,'A','C');   % methanol scenario label
    sB = ternary(fd<0.5,'B','D');   % ammonia scenario label

    fprintf('\n Baseline (net asset sum; gross = net x %.2f):\n', cfg0.f_packing);
    fprintf(' Option 1 import hub : Sc-%s %7.2f ha Sc-%s %7.2f ha\n', ...
        sA, base.opt1_total(2), sB, base.opt1_total(1));
    fprintf(' Option 2 production hub : Sc-%s %7.2f ha Sc-%s %7.2f ha\n', ...
        sA, base.opt2_total(2), sB, base.opt2_total(1));
    fprintf(' Electricity demand : Sc-%s %7.2f TWh Sc-%s %7.2f TWh\n', ...
        sA, base.E_total(2)/1e3, sB, base.E_total(1)/1e3);

    % Sweep table. Ranges are the literature ranges of Appendix B.
    %   fuels:   1 = NH3 only, 2 = MeOH only, 3 = both
    %   affects: 'A' area only, 'E' energy only, 'AE' both
    S = {
        'HB plant space [m2/tph]',    'amm_space_m2_per_tph',     [1593 3966 6339],            1, 'A'
        'MeOH synth space [m2/tph]',  'meth_space_m2_per_tph',    [1500 2487 4000],            2, 'A'
        'DAC space [m2/(t/yr)]',      'dac_space_m2_per_tCO2yr',  [0.002 0.10 0.56 1.33 2.0],  2, 'A'
        'Buffer days [d]',            'buffer_days',              [7 14 30 90],                3, 'A'
        'Yield factor [-]',           'yield_both',               [0.85 0.95 1.00],            3, 'AE'
        'Vessel packet scale [-]',    'packet_scale',             [6300/87000 0.5 1.0],        3, 'A'
        'NH3 fill fraction [-]',      'maxfill_ammonia',          [0.82 0.875 0.875],          1, 'A'
        'Max NH3 tank [m3]',          'maxtanksize_ammonia',      [60000 100000 181458],       1, 'A'
        'Electrolyser tech [1/2/3]',  'selected_elec',            [1 2 3],                     3, 'AE'
        'DAC energy [kWh/tCO2]',      'dac_energy_kWh_per_tCO2',  [769 2639 4006],             2, 'E'
        'ASU energy [MWh/t]',         'asu_energy_MWh_per_ton',   [0.114 0.311],               1, 'E'
        'MGO density [kg/m3]',        'rho_mgo',                  [810 850 890],               3, 'AE'
        };

    n = size(S,1);
    res = struct('name',{},'fuels',{},'affects',{}, ...
        'a_nh3',{},'a_meoh',{},'e_nh3',{},'e_meoh',{});

    fprintf('\n%s\n', repmat('-',1,W));
    fprintf(' %-27s %10s | %8s %8s | %7s %7s\n', ...
        'Parameter','Value','Opt2 NH3','Opt2 MeOH','E NH3','E MeOH');
    fprintf(' %-27s %10s | %8s %8s | %7s %7s\n', ...
        '','','[ha]','[ha]','[TWh]','[TWh]');
    fprintf('%s\n', repmat('-',1,W));

    for i = 1:n
        % One parameter at a time: set it, re-derive, re-run the whole chain,
        % record the two hub totals and the two energy totals.
        vals = S{i,3}; nv = numel(vals);
        a1 = nan(1,nv); a2 = nan(1,nv); e1 = nan(1,nv); e2 = nan(1,nv);
        for j = 1:nv
            cfg = fn_apply(cfg0, S{i,2}, vals(j));
            Rj  = fn_run_scenario(cfg, wind, fd, false, true);
            a1(j) = Rj.opt2_total(1); a2(j) = Rj.opt2_total(2);
            e1(j) = Rj.E_total(1)/1e3; e2(j) = Rj.E_total(2)/1e3;
            fprintf(' %-27s %10.4g | %8.2f %8.2f | %7.2f %7.2f\n', ...
                ternary(j==1, S{i,1}, ''), vals(j), a1(j), a2(j), e1(j), e2(j));
        end
        res(i).name    = S{i,1};
        res(i).fuels   = S{i,4};
        res(i).affects = S{i,5};
        res(i).a_nh3 = [min(a1) max(a1)]; res(i).a_meoh = [min(a2) max(a2)];
        res(i).e_nh3 = [min(e1) max(e1)]; res(i).e_meoh = [min(e2) max(e2)];
        fprintf('%s\n', repmat('-',1,W));
    end

    % Footprint and energy get separate tornadoes so that parameters reaching
    % only one of the two outputs have somewhere to appear.
    fn_tornado_filtered(res, 1, 'a_nh3',  base.opt2_total(1), cfg0.sens_min_swing_pct, ...
        sprintf('Sc-%s production hub (ammonia) — total footprint', sB), 'Total footprint [ha]');
    fn_tornado_filtered(res, 2, 'a_meoh', base.opt2_total(2), cfg0.sens_min_swing_pct, ...
        sprintf('Sc-%s production hub (methanol) — total footprint', sA), 'Total footprint [ha]');
    fn_tornado_filtered(res, 1, 'e_nh3',  base.E_total(1)/1e3, cfg0.sens_min_swing_pct, ...
        sprintf('Sc-%s (ammonia) — annual electricity demand', sB), 'Electricity demand [TWh/yr]');
    fn_tornado_filtered(res, 2, 'e_meoh', base.E_total(2)/1e3, cfg0.sens_min_swing_pct, ...
        sprintf('Sc-%s (methanol) — annual electricity demand', sA), 'Electricity demand [TWh/yr]');
end

function cfg = fn_apply(cfg, name, val)
% FN_APPLY Set one parameter and re-derive. yield_both is the one compound case.
    switch name
        case 'yield_both'
            cfg.yield_meth = val; cfg.yield_amm = val;
        otherwise
            cfg.(name) = val;
    end
    cfg = fn_derive(cfg);
end

function fn_tornado_filtered(res, fuel_idx, field, base_val, min_pct, ttl, xlab)

    is_energy = strncmp(field,'e_',2);
    nP = numel(res);
    keep = false(1,nP); why = cell(1,nP);

    for i = 1:nP
        % A bar is drawn only if the parameter is in this pathway, is a term
        % in this quantity, and moves it by more than the display threshold.
        applies_fuel = (res(i).fuels == 3) || (res(i).fuels == fuel_idx);
        if is_energy
            applies_qty = any(res(i).affects == 'E');
        else
            applies_qty = any(res(i).affects == 'A');
        end
        r = res(i).(field);
        swing_pct = (r(2)-r(1)) / base_val * 100;

        if ~applies_fuel
            why{i} = 'not present in this pathway';
        elseif ~applies_qty
            why{i} = ternary(is_energy, 'does not enter the energy balance', ...
                'does not enter any footprint term');
        elseif swing_pct < min_pct
            why{i} = sprintf('swing %.2f%%, below the %.1f%% display threshold', ...
                swing_pct, min_pct);
        else
            keep(i) = true;
        end
    end

    fprintf('\n %s\n', ttl);
    fprintf(' plotted: %d of %d parameters\n', sum(keep), nP);
    for i = find(~keep)
        fprintf(' omitted %-27s %s\n', res(i).name, why{i});
    end
    if ~any(keep)
        fprintf(' nothing exceeds the threshold, no figure drawn.\n');
        return
    end

    % Bars sorted by swing.
    idx = find(keep);
    swing = arrayfun(@(i) diff(res(i).(field)), idx);
    [~,o] = sort(swing,'ascend');
    idx = idx(o);
    nB = numel(idx);

    figure('Name',['Tornado — ' ttl],'Position',[120 120 950 max(300, 140+62*nB)]);
    hold on; grid on;
    for k = 1:nB
        r = res(idx(k)).(field);
        lo = r(1); hi = r(2);
        % Grey straddles the baseline, red sits above it, blue below.
        if lo < base_val && hi > base_val
            col = [0.45 0.45 0.45];
        elseif hi > base_val
            col = [0.78 0.24 0.20];
        else
            col = [0.12 0.47 0.71];
        end
        patch([lo hi hi lo],[k-0.32 k-0.32 k+0.32 k+0.32], col, ...
            'FaceAlpha',0.75,'EdgeColor','k');
        text(hi, k, sprintf(' %.4g (%+.0f%%)', hi, (hi-base_val)/base_val*100), ...
            'VerticalAlignment','middle','FontSize',9);
        text(lo, k, sprintf('(%+.0f%%) %.4g ', (lo-base_val)/base_val*100, lo), ...
            'VerticalAlignment','middle','HorizontalAlignment','right','FontSize',9);
    end
    xline(base_val,'k--','LineWidth',2);
    text(base_val, nB+0.62, sprintf('baseline %.4g', base_val), ...
        'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
    yticks(1:nB);
    yticklabels(arrayfun(@(i) res(i).name, idx, 'UniformOutput', false));
    xlabel(xlab);
    title(ttl,'FontSize',12,'FontWeight','bold');
    ylim([0.4, nB+0.9]);
    lo_all = min(arrayfun(@(i) min(res(i).(field)), idx));
    hi_all = max(arrayfun(@(i) max(res(i).(field)), idx));
    span = max(hi_all - lo_all, eps);
    xlim([lo_all - 0.30*span, hi_all + 0.30*span]);
end

function fn_storage_drivers(cfg0, wind)
% FN_STORAGE_DRIVERS The import hub holds only storage, berths, the truck
% station and the rail spur, so every upstream parameter is structurally
% unable to move it. The two that can, the buffer duration and the delivery
% parcel, are swept continuously instead of tornadoed. The buffer panel is
% what answers the IEA 90-day stockholding question directly.

    % Feasibility tiers of Section 4.6.1, drawn as reference lines.
    if ~isfield(cfg0,'parcel_lines_ha')
        parcels = [21, 50, 76.63];
        plabels = {'21 ha near-term acquisition','50 ha parcel','76.63 ha Outer Quayside'};
    else
        parcels = cfg0.parcel_lines_ha;
        plabels = arrayfun(@(x) sprintf('%.4g ha', x), parcels, 'UniformOutput', false);
    end

    buf_days  = [7 14 21 30 45 60 90];
    pkt_scale = [0.0833 0.25 0.5 0.75 1.0];
    levels    = [0.25 1.00];
    lvl_name  = {'25%','100%'};
    fuel_name = {'Ammonia','Methanol'};
    W = 88;

    fprintf('\n\n%s\n IMPORT HUB — STORAGE DRIVERS\n%s\n', repmat('=',1,W), repmat('=',1,W));
    fprintf(' Option 1 contains the tank farm, the berths, the truck station and the\n');
    fprintf(' rail spur. Every upstream parameter belongs to Option 2 and cannot enter\n');
    fprintf(' this total, so only the buffer duration and the delivery parcel move it.\n');

    % Both sweeps run the full chain rather than scaling the baseline, because
    % the tank count is an integer and the footprint therefore steps.
    % Buffer sweep. The tank count is an integer, so the footprint steps
    % rather than scaling, and each point has to be a full re-run.
    A_buf = zeros(numel(levels), 2, numel(buf_days));
    for L = 1:numel(levels)
        for k = 1:numel(buf_days)
            cfg = cfg0; cfg.buffer_days = buf_days(k); cfg = fn_derive(cfg);
            Rk = fn_run_scenario(cfg, wind, levels(L), false, true);
            A_buf(L,:,k) = Rk.opt1_total;
        end
    end

    % Parcel sweep, from a small coastal barge up to the reference carrier.
    A_pkt = zeros(numel(levels), 2, numel(pkt_scale));
    for L = 1:numel(levels)
        for k = 1:numel(pkt_scale)
            cfg = cfg0; cfg.packet_scale = pkt_scale(k); cfg = fn_derive(cfg);
            Rk = fn_run_scenario(cfg, wind, levels(L), false, true);
            A_pkt(L,:,k) = Rk.opt1_total;
        end
    end

    fprintf('\n Option 1 total [ha] against buffer days\n%s\n', repmat('-',1,W));
    fprintf(' %-22s', 'Scenario'); fprintf('%8d', buf_days); fprintf(' days\n');
    for L = 1:numel(levels)
        for f = 1:2
            fprintf(' %-22s', sprintf('%s %s', fuel_name{f}, lvl_name{L}));
            fprintf('%8.2f', squeeze(A_buf(L,f,:))); fprintf('\n');
        end
    end

    fprintf('\n Option 1 total [ha] against vessel packet (fraction of reference carrier)\n%s\n', ...
        repmat('-',1,W));
    fprintf(' %-22s', 'Scenario'); fprintf('%8.3g', pkt_scale); fprintf(' x packet\n');
    for L = 1:numel(levels)
        for f = 1:2
            fprintf(' %-22s', sprintf('%s %s', fuel_name{f}, lvl_name{L}));
            fprintf('%8.2f', squeeze(A_pkt(L,f,:))); fprintf('\n');
        end
    end
    fprintf('%s\n', repmat('-',1,W));

    cols = [0.12 0.47 0.71; 0.20 0.63 0.17];
    mk = {'-o','--s'};

    figure('Name','Import hub — storage drivers','Position',[120 120 1150 480]);
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on; grid on;
    for L = 1:numel(levels)
        for f = 1:2
            plot(buf_days, squeeze(A_buf(L,f,:)), mk{L}, 'Color', cols(f,:), ...
                'LineWidth',2,'MarkerFaceColor',cols(f,:),'MarkerSize',5, ...
                'DisplayName', sprintf('%s %s', fuel_name{f}, lvl_name{L}));
        end
    end
    for p = 1:numel(parcels)
        yline(parcels(p),':','Color',[0.4 0.4 0.4],'LineWidth',1.2, ...
            'Label',plabels{p},'LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
    xline(cfg0.buffer_days,'k--','LineWidth',1.5,'HandleVisibility','off');
    xlabel('Buffer days [d]'); ylabel('Option 1 total footprint [ha]');
    title('Sensitivity to the strategic buffer','FontSize',12,'FontWeight','bold');
    legend('Location','northwest','FontSize',9);
    set(gca,'YScale','log');

    nexttile; hold on; grid on;
    pkt_m3 = pkt_scale * cfg0.packet_meth / 1000;
    for L = 1:numel(levels)
        for f = 1:2
            plot(pkt_m3, squeeze(A_pkt(L,f,:)), mk{L}, 'Color', cols(f,:), ...
                'LineWidth',2,'MarkerFaceColor',cols(f,:),'MarkerSize',5, ...
                'DisplayName', sprintf('%s %s', fuel_name{f}, lvl_name{L}));
        end
    end
    xlabel('Vessel packet [1000 m^3]'); ylabel('Option 1 total footprint [ha]');
    title('Sensitivity to the delivery parcel','FontSize',12,'FontWeight','bold');
    legend('Location','northwest','FontSize',9);
    set(gca,'YScale','log');

    sgtitle('Import hub footprint — the only two parameters that reach it', ...
        'FontSize',13,'FontWeight','bold');
end

function fn_distribution_drivers(cfg0, wind)
% FN_DISTRIBUTION_DRIVERS Modal-split and bunker-rate sweeps, Section 4.7.7.
% The split is a three-component allocation, so it is run as a set of bounding
% allocations rather than swept as a scalar.

    splits = [0.70 0.20 0.10;
              1.00 0.00 0.00;
              0.50 0.25 0.25;
              0.00 1.00 0.00;
              0.00 0.00 1.00];
    Qb = [500 1000 2000];
    levels = [0.25 1.00];
    fuel_name = {'Ammonia','Methanol'};
    W = 88;
    fprintf('\n\n%s\n DISTRIBUTION DRIVERS: MODAL SPLIT AND BUNKER TRANSFER RATE\n%s\n', ...
        repmat('=',1,W), repmat('=',1,W));

    for L = 1:numel(levels)
        for s = 1:size(splits,1)
            cfg = cfg0;
            cfg.percentage_pipe  = splits(s,1);
            cfg.percentage_rail  = splits(s,2);
            cfg.percentage_truck = splits(s,3);
            cfg = fn_derive(cfg);
            R = fn_run_scenario(cfg, wind, levels(L), false, true);
            fprintf(' %4.2f/%4.2f/%4.2f lvl %3.0f%% Opt1 NH3 %6.2f MeOH %6.2f ha', ...
                splits(s,:), levels(L)*100, R.opt1_total(1), R.opt1_total(2));
            fprintf('  gross %6.2f / %6.2f ha\n', R.opt1_gross(1), R.opt1_gross(2));
            % Land-side detail behind the totals: the rail corridor is what
            % moves, through the platform count once the 740 m cap binds.
            for f = [2 1]
                fprintf('     %-9s wagons %3d trains %5d/yr %5.2f/op-day platforms %d ', ...
                    fuel_name{f}, R.n_carts(f), R.n_trains(f), R.trains_per_day(f), R.n_platforms(f));
                fprintf('bays %2d land-side %6.2f ha\n', R.N_bays(f), ...
                    (R.A_rail_safety(f) + R.A_truck_safety(f))/1e4);
            end
        end
    end

    for L = 1:numel(levels)
        for q = 1:numel(Qb)
            cfg = cfg0; cfg.Q_bkr = Qb(q); cfg = fn_derive(cfg);
            R = fn_run_scenario(cfg, wind, levels(L), false, true);
            fprintf(' Q=%5d lvl %3.0f%% berths %d/%d quay %4.0f/%4.0f m Opt1 %6.2f/%6.2f ha\n', ...
                Qb(q), levels(L)*100, R.N_berth(1), R.N_berth(2), ...
                R.L_quay(1), R.L_quay(2), R.opt1_total(1), R.opt1_total(2));
        end
    end
end

function fn_feasibility(runs, SC)
% FN_FEASIBILITY Both hub totals against the five-tier land inventory of
% Section 4.6.1. The tiers are case data, not model output, so they are
% listed here and compared rather than derived. Section 3.6.5 assigns the
% verdict on the gross figure wherever the packing allowance changes the tier.

    % Case data from Section 4.6.1, not model output: the parcels the port
    % actually has, in ascending order.
    tiers = [20.30, 21.00, 49.52, 76.63, 286.89];
    names = {'Integrated Fuel-Cluster','acquisition threshold', ...
             'Central Quarry','Outer Quayside','opportunistic reclamation'};
    W = 96;
    fprintf('\n\n%s\n SPATIAL FEASIBILITY AGAINST THE PORT LAND INVENTORY\n%s\n', ...
        repmat('=',1,W), repmat('=',1,W));
    for t = 1:numel(tiers)
        fprintf(' tier %d  %-26s %7.2f ha\n', t, names{t}, tiers(t));
    end
    fprintf('%s\n', repmat('-',1,W));
    fprintf(' %-12s %9s %9s  %-28s %-28s\n', ...
        'Scenario','Net [ha]','Gross [ha]','Smallest tier (net)','Smallest tier (gross)');
    for opt = 1:2
        if opt == 1
            fprintf(' Option 1 — import hub\n');
            fn = 'opt1_total'; fg = 'opt1_gross';
        else
            fprintf(' Option 2 — production hub\n');
            fn = 'opt2_total'; fg = 'opt2_gross';
        end
        for s = 1:4
            net   = runs{SC(s).run}.(fn)(SC(s).fuel);
            gross = runs{SC(s).run}.(fg)(SC(s).fuel);
            fprintf('   Sc-%-9s %9.2f %9.2f  %-28s %-28s\n', SC(s).label, ...
                net, gross, fn_tier(net, tiers, names), fn_tier(gross, tiers, names));
        end
    end
    fprintf('%s\n', repmat('-',1,W));
    fprintf(' Decentralisation, which relocates the electrolyser and the DAC unit off\n');
    fprintf(' site, is applied by hand where the centralised verdict fails.\n');
end

function lab = fn_tier(A, tiers, names)
% FN_TIER Smallest parcel that accommodates area A.
    i = find(tiers >= A, 1);
    if isempty(i), lab = 'exceeds all parcels';
    else, lab = names{i};
    end
end

function fn_packing_sweep(runs, SC, cfg)
% FN_PACKING_SWEEP The gross figure is the net asset sum times one scalar, so
% this sweep is exact rather than a re-run of the chain. Section 4.7.4.

    % Packing enters as a single multiplier on the asset sum, so the sweep is
    % exact arithmetic on the finished totals.
    fp = [1.00 1.35 1.50 2.00 2.50];
    W = 78;
    fprintf('\n\n%s\n GROSS-TO-NET PACKING SWEEP\n%s\n', repmat('=',1,W), repmat('=',1,W));
    for opt = 1:2
        if opt == 1
            fprintf('\n Option 1 — import hub [ha]\n'); fld = 'opt1_total';
        else
            fprintf('\n Option 2 — production hub [ha]\n'); fld = 'opt2_total';
        end
        fprintf(' %-22s %9s %9s %9s %9s\n', 'f_packing', 'Sc-A','Sc-B','Sc-C','Sc-D');
        for k = 1:numel(fp)
            lab = sprintf('%.2f', fp(k));
            if abs(fp(k)-cfg.f_packing) < 1e-9, lab = [lab ' (baseline)']; end
            fprintf(' %-22s', lab);
            for s = 1:4
                fprintf(' %9.2f', runs{SC(s).run}.(fld)(SC(s).fuel) * fp(k));
            end
            fprintf('\n');
        end
    end
end

function fn_elyz_ratio_sweep(cfg0, wind)
    % Full span of the surveyed PEM systems. 
    ratios = [0.0075 0.10 0.20 0.349];
    levels = [0.25 1.00];
    W = 78;
    fprintf('\n\n%s\n ELECTROLYSER FOOTPRINT RATIO SWEEP\n%s\n', repmat('=',1,W), repmat('=',1,W));
    fprintf(' %-16s %10s %10s %10s %10s\n', 's_e [m2/(kg/d)]', ...
        'elec NH3','elec MeOH','Opt2 NH3','Opt2 MeOH');
    for L = 1:numel(levels)
        fprintf(' demand level %.0f%% [ha]\n', levels(L)*100);
        for k = 1:numel(ratios)
            cfg = cfg0;
            cfg.elec_fp_ratio(cfg.selected_elec) = ratios(k);
            cfg = fn_derive(cfg);
            R = fn_run_scenario(cfg, wind, levels(L), false, true);
            fprintf(' %-16.4g %10.2f %10.2f %10.2f %10.2f\n', ratios(k), ...
                R.elec_ha(1), R.elec_ha(2), R.opt2_total(1), R.opt2_total(2));
        end
    end
end

function fn_supply_compare(cfg0)
% FN_SUPPLY_COMPARE The intermittent SE3 profile against a constant supply
    levels = [0.25 1.00];
    W = 88;
    fprintf('\n\n%s\n RENEWABLE SUPPLY PROFILE: %s AGAINST CONSTANT SUPPLY\n%s\n', ...
        repmat('=',1,W), upper(cfg0.power_mode), repmat('=',1,W));

    % Constant supply is a different profile, not a different parameter, so
    % it needs its own resource load and its own pass through the chain.
    cfgC = cfg0; cfgC.power_mode = 'Continuous'; cfgC = fn_derive(cfgC);
    windW = fn_load_wind(cfg0);
    windC = fn_load_wind(cfgC);

    fprintf(' Effective electrolyser CF: %s %.3f, continuous %.3f\n', ...
        cfg0.power_mode, windW.elyz_CF, windC.elyz_CF);
    fprintf(' %-30s %10s %10s %10s %10s\n', 'Quantity', 'NH3 wind','NH3 cont','MeOH wind','MeOH cont');

    for L = 1:numel(levels)
        RW = fn_run_scenario(cfg0, windW, levels(L), false, true);
        RC = fn_run_scenario(cfgC, windC, levels(L), false, true);
        fprintf('%s\n demand level %.0f%%\n', repmat('-',1,W), levels(L)*100);
        row = @(lab, a, b, c, d, fmt) fprintf([' %-30s ' fmt ' ' fmt ' ' fmt ' ' fmt '\n'], lab, a, b, c, d);
        row('Electrolyser capacity [GW]', RW.elyz_GW(1), RC.elyz_GW(1), RW.elyz_GW(2), RC.elyz_GW(2), '%10.2f');
        row('Electrolyser area [ha]',     RW.elec_ha(1), RC.elec_ha(1), RW.elec_ha(2), RC.elec_ha(2), '%10.2f');
        row('Total H2 buffer [t]',        RW.buf_kg(1)/1e3, RC.buf_kg(1)/1e3, RW.buf_kg(2)/1e3, RC.buf_kg(2)/1e3, '%10.0f');
        row('Buffer duration [days]',     RW.buf_days(1), RC.buf_days(1), RW.buf_days(2), RC.buf_days(2), '%10.1f');
        row('On-site sphere array [ha]',  RW.sph_A_safety(1)/1e4, RC.sph_A_safety(1)/1e4, ...
                                          RW.sph_A_safety(2)/1e4, RC.sph_A_safety(2)/1e4, '%10.2f');
        row('Electricity demand [TWh/yr]',RW.E_total(1)/1e3, RC.E_total(1)/1e3, RW.E_total(2)/1e3, RC.E_total(2)/1e3, '%10.2f');
        row('Production hub net [ha]',    RW.opt2_total(1), RC.opt2_total(1), RW.opt2_total(2), RC.opt2_total(2), '%10.2f');
    end
    fprintf('%s\n', repmat('-',1,W));
end

function fn_terminal_mode_compare(cfg0, wind)
%Simulated peak inventory under the two operating
% modes.

    levels = [0.25 1.00];
    W = 78;
    fprintf('\n\n%s\n TERMINAL OPERATING MODE: SIMULATED PEAK INVENTORY [1000 m3]\n%s\n', ...
        repmat('=',1,W), repmat('=',1,W));
    fprintf(' %-26s %10s %10s %10s %10s\n', 'Basis', 'Sc-A','Sc-B','Sc-C','Sc-D');

    peak = zeros(2,4);   % row 1 = batch-export, row 2 = continuous-offtake
    modes = {'export','bunker'};
    for m = 1:2
        cfg = cfg0; cfg.terminal_mode = modes{m}; cfg = fn_derive(cfg);
        for L = 1:numel(levels)
            R = fn_run_scenario(cfg, wind, levels(L), false, true);
            peak(m, (L-1)*2+1) = R.sim_max_inv(2);   % methanol -> Sc-A, Sc-C
            peak(m, (L-1)*2+2) = R.sim_max_inv(1);   % ammonia  -> Sc-B, Sc-D
        end
    end
    ord = [1 2 3 4];
    fprintf(' %-26s', 'Batch-export (baseline)');
    fprintf(' %10.1f', peak(1,ord)/1e3); fprintf('\n');
    fprintf(' %-26s', 'Continuous-offtake');
    fprintf(' %10.1f', peak(2,ord)/1e3); fprintf('\n');
    fprintf(' %-26s', 'Difference [%]');
    fprintf(' %10.1f', (peak(2,ord)./peak(1,ord) - 1)*100); fprintf('\n');
end

function fn_param_position_table(cfg)
% Where each adopted value sits in its literature
% range.

    W = 104;
    fprintf('\n\n%s\n PARAMETER POSITION IN LITERATURE RANGE (generated from cfg)\n%s\n', ...
        repmat('=',1,W), repmat('=',1,W));
    fprintf(' %-26s %10s %10s %10s %8s %s\n', ...
        'Parameter','Low','Used','High','Pos [%]','Bias on footprint');
    fprintf('%s\n', repmat('-',1,W));

    P = {
        'MGO density',        810,    cfg.rho_mgo,                890,   'volumes constant'
        'DAC space factor',   0.002,  cfg.dac_space_m2_per_tCO2yr, 2.0,  'optimistic: below Orca 0.56 / Mammoth 1.33'
        'DAC energy',         769,    cfg.dac_energy_kWh_per_tCO2, 4006, 'mid'
        'MeOH synth space',   2487,   cfg.meth_space_m2_per_tph,  2487,  'single reference facility (Kasso)'
        'HB plant space',     1593,   cfg.amm_space_m2_per_tph,   6339,  'optimistic: flips the Sc-B verdict at the top'
        'HB specific energy', 0.934,  cfg.amm_energy_MWh_per_ton, 0.97,  'conservative'
        'ASU energy',         0.114,  cfg.asu_energy_MWh_per_ton, 0.311, 'optimistic'
        'PEM footprint ratio',0.0075, cfg.elec_fp_ratio(2),       0.349, 'conservative'
        'PEM specific energy',49.9,   cfg.elec_eff(2),            55.9,  'conservative'
        'NH3 fill fraction',  0.82,   cfg.maxfill_ammonia,        0.875, 'optimistic (borrowed from non-refrigerated rule)'
        'Peak factor k',      1,      cfg.peak_factor,            5,     'conservative (pipelines only)'
        'Yield factor',       0.85,   cfg.yield_meth,             1.00,  'optimistic'
        'Buffer days',        7,      cfg.buffer_days,            90,    'optimistic (IEA 90-day obligation assumed not to apply)'
        'Packing factor',     1.00,   cfg.f_packing,              2.50,  'gross-to-net allowance'
        };

    for i = 1:size(P,1)
        lo = P{i,2}; used = P{i,3}; hi = P{i,4};
        if hi > lo, pos = (used-lo)/(hi-lo)*100; else, pos = NaN; end
        fprintf(' %-26s %10.4g %10.4g %10.4g %8.0f %s\n', ...
            P{i,1}, lo, used, hi, pos, P{i,5});
    end
    fprintf('%s\n', repmat('-',1,W));
    fprintf(' Position 0%% = low end of the range, 100%% = high end. This table is\n');
    fprintf(' the machine-readable version of the convention stated in Section 3.3.2.\n');
end

% -------------------------------------------------------------------------
% CURVE-FIT DIAGNOSTICS — Appendix B.2
% -------------------------------------------------------------------------

function fn_fit_diagnostics()
% FN_FIT_DIAGNOSTICS The wall-thickness and H/D regressions of Eqs. 3.17,
% 3.18 and 3.20 with their goodness of fit, residuals and a power-law
% alternative. The dataset is Table B.5. The interpretation is printed next
% to the statistics so the appendix text and the model cannot disagree.

    W = 78;
    fprintf('\n\n%s\n APPENDIX B.2 — CURVE-FIT DIAGNOSTICS\n%s\n', ...
        repmat('=',1,W), repmat('=',1,W));

    % ── Annular insulation thickness, linear in volume, Eq. 3.20 ─────────
    % Built-tank data behind the geometry fits. Small samples, so the
    % goodness of fit is reported alongside every coefficient.
    x_wall = [45999.69272; 45000; 15383.49245; 7551.431358; 15393.8008];
    y_wall = [1; 1; 0.8; 0.8; 0.765];
    p_wall = polyfit(x_wall, y_wall, 1);
    yh = polyval(p_wall, x_wall);
    R2_w = 1 - sum((y_wall-yh).^2)/sum((y_wall-mean(y_wall)).^2);

    fprintf('\n Wall thickness (linear): t = %.6e * V + %.4f R2 = %.3f (n = %d)\n', ...
        p_wall(1), p_wall(2), R2_w, numel(x_wall));
    fprintf(' residuals [m]: '); fprintf('%+.3f ', y_wall-yh); fprintf('\n');

    figure('Name','A.1 — Tank Capacity vs Wall Thickness','Color','w');
    xl = linspace(0, 55000, 100);
    scatter(x_wall, y_wall, 100, 'filled', 'MarkerFaceColor', '#004B87', ...
        'DisplayName','Data points'); hold on;
    plot(xl, polyval(p_wall,xl), '--', 'Color','#E74C3C','LineWidth',2, ...
        'DisplayName', sprintf('Linear fit (R^2 = %.3f)', R2_w));
    title('Tank Capacity vs. Wall Thickness','FontSize',14);
    xlabel('Tank Capacity (m^3)','FontSize',12,'FontWeight','bold');
    ylabel('Wall Thickness (m)','FontSize',12,'FontWeight','bold');
    xlim([0 55000]); ylim([0.6 1.2]); grid on;
    legend('Location','southeast','FontSize',11);

    % ── H/D ratio, exponential (used) and power law (alternative) ────────
    v_meth  = [13000; 24736.103; 28902.6464; 100000; 40000; 80000];
    hd_meth = [0.85; 0.530769231; 0.575; 0.2725; 0.346153846; 0.281420765];

    v_amm   = [60000; 181458.3539; 15393.8008; 16456.00447; 29370; ...
               45999.69272; 45000; 15383.49245; 7551.431358];
    hd_amm  = [0.472727273; 0.526315789; 0.457142857; 0.381842105; 0.742105263; ...
               1.067368421; 0.735632184; 0.941818182; 0.929325379];

    [a_m, b_m, R2_m, res_m] = fn_expfit(v_meth, hd_meth);
    [a_a, b_a, R2_a, res_a] = fn_expfit(v_amm,  hd_amm);
    [c_m, d_m, R2pm] = fn_powfit(v_meth, hd_meth);
    [c_a, d_a, R2pa] = fn_powfit(v_amm,  hd_amm);

    fprintf('\n H/D ratio fits (R2 computed on the fitted values, not on log H/D):\n');
    fprintf(' Methanol exponential : R = %.4f * exp(%.3e * V) R2 = %.3f (n = %d)\n', ...
        a_m, b_m, R2_m, numel(v_meth));
    fprintf(' Methanol power law : R = %.3f * V^(%.4f) R2 = %.3f\n', c_m, d_m, R2pm);
    fprintf(' Ammonia exponential : R = %.4f * exp(%.3e * V) R2 = %.3f (n = %d)\n', ...
        a_a, b_a, R2_a, numel(v_amm));
    fprintf(' Ammonia power law : R = %.3f * V^(%.4f) R2 = %.3f\n', c_a, d_a, R2pa);
    fprintf(' Ammonia constant : mean H/D = %.3f, sd = %.3f, range %.2f-%.2f\n', ...
        mean(hd_amm), std(hd_amm), min(hd_amm), max(hd_amm));
    fprintf(' Ammonia residuals : '); fprintf('%+.3f ', res_a); fprintf('\n');
    fprintf(' Methanol residuals : '); fprintf('%+.3f ', res_m); fprintf('\n');

    band_a = std(hd_amm)/mean(hd_amm)*100;
    band_m = std(hd_meth)/mean(hd_meth)*100;

    fprintf('\n Interpretation\n');
    fprintf(' Ammonia : R2 = %.3f. The fit varies only from %.3f to %.3f across the\n', ...
        R2_a, a_a*exp(b_a*min(v_amm)), a_a*exp(b_a*max(v_amm)));
    fprintf(' 7 000-181 000 m3 range, so it acts as a constant near the\n');
    fprintf(' population mean of %.3f. Built H/D scatters %.2f-%.2f, a\n', ...
        mean(hd_amm), min(hd_amm), max(hd_amm));
    fprintf(' coefficient of variation of %.0f%%. The fitted value is used as\n', band_a);
    fprintf(' a central indication within that experienced range, and the\n');
    fprintf(' scatter is carried as a %.0f%% band on H/D, hence on D_out,\n', band_a);
    fprintf(' shell spacing and the Layer 1 and Layer 3 areas.\n');
    fprintf(' Methanol : R2 = %.3f exponential, %.3f power law, coefficient of\n', R2_m, R2pm);
    fprintf(' variation %.0f%%. The trend to flatter tanks with size is\n', band_m);
    fprintf(' real in this dataset; the power law describes it better.\n');
    fprintf(' Check : the 46 000 m3 ammonia point at H/D = 1.07 implies a flat-bottom\n');
    fprintf(' refrigerated tank taller than it is wide, and it is the point\n');
    fprintf(' most responsible for lifting the fit. Verify that row.\n');

    figure('Name','A.2 — H/D Ratio vs Tank Capacity','Color','w');
    v_line = linspace(1, 200000, 300);
    scatter(v_meth, hd_meth, 100, 'filled','MarkerFaceColor','#004B87', ...
        'DisplayName','Methanol tanks'); hold on;
    plot(v_line, a_m*exp(b_m*v_line), '--','Color','#004B87','LineWidth',2, ...
        'DisplayName', sprintf('MeOH exp (R^2 = %.2f)', R2_m));
    plot(v_line, c_m*v_line.^d_m, ':','Color','#004B87','LineWidth',2, ...
        'DisplayName', sprintf('MeOH power (R^2 = %.2f)', R2pm));
    scatter(v_amm, hd_amm, 100,'square','filled','MarkerFaceColor','#229954', ...
        'DisplayName','Ammonia tanks');
    plot(v_line, a_a*exp(b_a*v_line), '--','Color','#229954','LineWidth',2, ...
        'DisplayName', sprintf('NH_3 exp (R^2 = %.2f)', R2_a));
    yline(mean(hd_amm), '-.', sprintf('NH_3 mean %.2f', mean(hd_amm)), ...
        'Color','#229954','LineWidth',1.5,'HandleVisibility','off');
    title('H/D Ratio vs. Tank Capacity','FontSize',14);
    xlabel('Tank Capacity (m^3)','FontSize',12,'FontWeight','bold');
    ylabel('H/D Ratio','FontSize',12,'FontWeight','bold');
    xlim([0 200000]); ylim([0 1.2]); grid on;
    legend('Location','northeast','FontSize',10);
end

function [a, b, R2, res] = fn_expfit(v, y)
    p = polyfit(v, log(y), 1);
    b = p(1); a = exp(p(2));
    yh = a*exp(b*v);
    res = y - yh;
    R2 = 1 - sum(res.^2)/sum((y-mean(y)).^2);
end

function [c, d, R2] = fn_powfit(v, y)
    p = polyfit(log(v), log(y), 1);
    d = p(1); c = exp(p(2));
    yh = c*v.^d;
    R2 = 1 - sum((y-yh).^2)/sum((y-mean(y)).^2);
end

% -------------------------------------------------------------------------
% PLOTTING
% -------------------------------------------------------------------------

function fn_plot_tank_layout(fuel, lvl, nt, D_o, D_i, d_sh, d_btw, is_dwdi, ...
    n_pg_max, w1,h1, w2,h2, w3,h3, tcol)
% Three-layer storage footprint drawn to scale, Figures 3.4-3.6 and 4.1-4.2.
% The three envelopes are concentric about the Layer 1 centre.

    figure('Name', sprintf('3.6.1 — %s Layout %s (%d tanks)', fuel, lvl, nt), ...
        'Position',[150 150 850 650]);
    hold on; axis equal;

    cx = w1/2; cy = h1/2;
    rectangle('Position',[cx-w3/2, cy-h3/2, w3, h3], 'EdgeColor','r', ...
        'LineStyle','--','LineWidth',1.5,'FaceColor',[1 0 0 0.05]);
    rectangle('Position',[cx-w2/2, cy-h2/2, w2, h2], 'EdgeColor',[0.9 0.75 0], ...
        'LineStyle','-','LineWidth',1.5,'FaceColor',[1 1 0 0.15]);
    rectangle('Position',[0,0,w1,h1],'EdgeColor','k','LineStyle',':','LineWidth',1.2);

    % Tanks drawn group by group, left to right, at true relative scale.
    grps = fn_group_split(nt, n_pg_max);
    pitch = D_o + d_sh;                  % Eq. 3.25
    cur_x = 0;
    for i = 1:numel(grps)
        [nr, nc] = fn_grid(grps(i));
        W_grp = (nc-1)*pitch + D_o;
        for r = 1:nr
            for c = 1:nc
                if (r-1)*nc + c <= grps(i)
                    tx = cur_x + D_o/2 + (c-1)*pitch;
                    ty = D_o/2 + (r-1)*pitch;
                    if is_dwdi
                        % Outer shell drawn around the inner vessel.
                        rectangle('Position',[tx-D_o/2, ty-D_o/2, D_o, D_o], ...
                            'Curvature',[1 1],'FaceColor',[0.95 0.95 0.95], ...
                            'EdgeColor','k','LineWidth',1.5);
                        rectangle('Position',[tx-D_i/2, ty-D_i/2, D_i, D_i], ...
                            'Curvature',[1 1],'FaceColor',tcol,'EdgeColor','k');
                    else
                        rectangle('Position',[tx-D_o/2, ty-D_o/2, D_o, D_o], ...
                            'Curvature',[1 1],'FaceColor',tcol,'EdgeColor','k');
                    end
                end
            end
        end
        cur_x = cur_x + W_grp + d_btw;
    end

    title(sprintf('%s Storage Footprint — %s demand (%d tanks)\nSafety W=%.0f m, H=%.0f m', ...
        fuel, lvl, nt, w3, h3),'FontSize',12,'FontWeight','bold');
    xlabel('Width [m]'); ylabel('Depth [m]');
    pad = 30;
    xlim([cx-w3/2-pad, cx+w3/2+pad]); ylim([cy-h3/2-pad, cy+h3/2+pad]); grid on;

    h_L3 = patch(NaN,NaN,'r','FaceAlpha',0.1,'EdgeColor','r','LineStyle','--','LineWidth',1.5);
    h_L2 = patch(NaN,NaN,'y','FaceAlpha',0.3,'EdgeColor',[0.9 0.75 0],'LineStyle','-','LineWidth',1.5);
    h_L1 = plot(NaN,NaN,'k:','LineWidth',1.5);
    h_T  = plot(NaN,NaN,'o','MarkerEdgeColor','k','MarkerFaceColor',tcol,'MarkerSize',8);
    if is_dwdi
        legend([h_L3,h_L2,h_L1,h_T],{'Layer 3 (Safety)','Layer 2 (Containment)', ...
            'Layer 1 (Hardware)','Storage Tank'},'Location','northeast');
    else
        legend([h_L3,h_L2,h_L1,h_T],{'Layer 3 (Safety)','Layer 2 (Bund)', ...
            'Layer 1 (Hardware)','Storage Tank'},'Location','northeast');
    end
end

function fn_plot_inventory(fuel, lvl, inv, min_buf, max_inv, nominal, ships, pkt, cfg)
% Simulated inventory trajectory, Figures 4.3-4.4. Upper panel is the full
% year, lower panel a six-week zoom with the weekend halts shaded, which is
% the part the simulation actually contributes over Eq. 3.11.

    hpy = cfg.hours_per_year;
    figure('Name', sprintf('3.6.2 — %s Inventory %s', fuel, lvl), 'Position',[100 100 1200 650]);

    subplot(2,1,1);
    plot(1:hpy, inv, '-','LineWidth',1.2,'Color','#08519c'); hold on; grid on;
    yline(min_buf,'--r',sprintf('%d-day buffer', cfg.buffer_days),'LineWidth',1.5);
    yline(max_inv,':k','Max working vol','LineWidth',1.0);
    if strcmp(cfg.terminal_mode,'export')
        title(sprintf('%s (%s) Full Year — %d vessel calls (%d m^3). Peak = packet + buffer by construction', ...
            fuel, lvl, ships, round(pkt)));
    else
        title(sprintf('%s (%s) Full Year — continuous bunker offtake', fuel, lvl));
    end
    xlabel('Hour of year'); ylabel('Inventory [m^3]');
    xlim([0 hpy]); ylim([0 nominal*1.1]);

    subplot(2,1,2);
    z0 = 24*7*8; z1 = z0 + 24*7*6;
    plot(1:hpy, inv, '-','LineWidth',1.5,'Color','#31a354'); hold on; grid on;
    % Shade the weekends so the sawtooth from the five-day reception calendar
    % is visible against a continuous offtake.
    for w = 8:14
        ws = (w*7*24) - (2*24);
        patch([ws ws+48 ws+48 ws],[0 0 nominal*1.2 nominal*1.2], ...
            [0.8 0.8 0.8],'FaceAlpha',0.3,'EdgeColor','none');
    end
    xlim([z0 z1]);
    ylim([min(inv(z0:z1))-5000, max(inv(z0:z1))+5000]);
    title(sprintf('%s (%s) Zoomed — weekend halts vs. offtake', fuel, lvl));
    xlabel('Hour of year'); ylabel('Inventory [m^3]');
end

function fn_plot_h2_buffer(fuel, lvl, S_prof, tk_kg, cap_pct, dH2, buf_k, cfg)
% Shifted net-flow trajectory S(d) of Eq. 3.83 at each capacity ratio, with
% the 5-day minimum and the 1-day on-site mass marked.

    dpy = cfg.days_per_year;
    n_scen = numel(cap_pct);
    month_ticks_d = cumsum([1 31 28 31 30 31 30 31 31 30 31 30]) - 15;
    month_lbls = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};

    figure('Name', sprintf('3.6.4 — H2 Buffer: %s %s', fuel, lvl), 'Position',[150 50 600 900]);
    tl = tiledlayout(n_scen,1,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('H_2 Buffer — %s Pathway, %s demand', fuel, lvl), ...
        'FontSize',12,'FontWeight','bold');

    for s = 1:n_scen
        nexttile;
        Sv = S_prof{s};
        area(1:dpy, Sv/1e3,'FaceColor',[0.12 0.47 0.71],'FaceAlpha',0.25,'EdgeColor','none');
        hold on;
        plot(1:dpy, Sv/1e3,'Color',[0.12 0.47 0.71],'LineWidth',1.8);
        yline(buf_k/1e3,'r--','5-Day Min','LineWidth',1.2,'LabelHorizontalAlignment','left');
        yline(tk_kg(s)/1e3,'k--','LineWidth',1.2);
        yline(dH2/1e3,'b--','1-Day Onsite','LineWidth',1.5,'LabelHorizontalAlignment','right');
        title(sprintf('r=%.2f | Tank: %.0f t (%.1f days)', cap_pct(s)/100, ...
            tk_kg(s)/1e3, tk_kg(s)/dH2),'FontSize',9);
        ylabel('H_2 [t]');
        xticks(month_ticks_d); xticklabels(month_lbls); xlim([1 dpy]); grid on;
    end
end

function fn_plot_spheres(fuel, lvl, grps, D_out_s, d_intra, d_inter, Lp)
% LH2 sphere pad layout, Appendix B.3. Same grid and group logic as the tank
% farm, with the hydrogen spacing rules of Table B.12 substituted in.

    N = sum(grps);
    figure('Name', sprintf('LH2 Spheres — %s %s (%d)', fuel, lvl, N), ...
        'Position',[150 150 900 400]);
    hold on; axis equal;

    cur_x = 0;
    for i = 1:numel(grps)
        [nr, nc] = fn_grid(grps(i));
        W_grp = nc*D_out_s + max(0,nc-1)*d_intra;
        L_grp = nr*D_out_s + max(0,nr-1)*d_intra;
        rectangle('Position',[cur_x,0,W_grp,L_grp],'EdgeColor','k','LineStyle','--','LineWidth',1.2);
        for r = 1:nr
            for c = 1:nc
                if (r-1)*nc + c <= grps(i)
                    cx = cur_x + D_out_s/2 + (c-1)*(D_out_s+d_intra);
                    cy = D_out_s/2 + (r-1)*(D_out_s+d_intra);
                    rectangle('Position',[cx-D_out_s/2, cy-D_out_s/2, D_out_s, D_out_s], ...
                        'Curvature',[1 1],'FaceColor',[0.12 0.47 0.71],'EdgeColor','k');
                end
            end
        end
        cur_x = cur_x + W_grp + d_inter;
    end

    title(sprintf('%s (%s) — LH_2 Sphere Layout: %d tanks [%s]', fuel, lvl, N, num2str(grps)), ...
        'FontSize',11,'FontWeight','bold');
    xlabel('Width [m]'); ylabel('Depth [m]');
    xlim([-10, cur_x - d_inter + 10]); ylim([-10, Lp+10]); grid on;
end

function fn_plot_tradeoff(cfg, wind, H2_day, fuel_name, lvl)
% System trade-off sweep of Section 3.6.4: r from 0.20 to 1.00 against
% generation capacity, electrolyser capacity, exportable surplus (Eq. 3.79)
% and buffer size. This is the figure the baseline r is read off.

    hpy = cfg.hours_per_year; dpy = cfg.days_per_year; e = cfg.selected_elec;
    ratio_range = 0.20:0.05:1.00;
    nr = numel(ratio_range);

    for f = 1:2
        dH2 = H2_day(f);
        buf = dH2 * cfg.min_buf_days;
        E_req = dH2 * cfg.elec_eff(e) * dpy / 1e6;
        wGW = zeros(1,nr); eGW = zeros(1,nr); exc = zeros(1,nr); tnk = zeros(1,nr);

        % Sweep the capacity ratio and record what each choice costs: farm
        % size, electrolyser size, spilled energy and buffer mass.
        for k = 1:nr
            r = ratio_range(k);
            p_use = sum(min(wind.hourly_GW, r*wind.cap_GW)) / wind.annual_GWh;
            w  = E_req / (wind.CF * p_use * hpy);
            eg = w * r;
            wGW(k) = w; eGW(k) = eg;
            exc(k) = (w * wind.CF * hpy) - E_req;

            hw = wind.hourly_GW * (w / wind.cap_GW);
            dp = zeros(dpy,1);
            for d = 1:dpy
                dp(d) = sum(min(hw((d-1)*24+1:d*24), eg))*1e6 / cfg.elec_eff(e);
            end
            cn = cumsum(dp - dH2);
            tnk(k) = max(cn - min(cn) + buf)/1000;
        end

        fprintf('\n Trade-off sweep — %s, %s demand (Section 4.5.1)\n', fuel_name{f}, lvl);
        fprintf(' %6s %10s %10s %12s %10s %10s\n', ...
            'r', 'wind [GW]', 'elyz [GW]', 'export [GWh]', 'buffer [t]', 'capture [%]');
        for k = 1:nr
            r = ratio_range(k);
            cap_pct_k = sum(min(wind.hourly_GW, r*wind.cap_GW)) / wind.annual_GWh * 100;
            fprintf(' %6.2f %10.2f %10.2f %12.0f %10.0f %10.1f\n', ...
                r, wGW(k), eGW(k), exc(k), tnk(k), cap_pct_k);
        end

        figure('Name', sprintf('3.6.4 — Trade-off: %s %s', fuel_name{f}, lvl), ...
            'Position',[120 50 850 950]);
        sgtitle(sprintf('%s PATHWAY (%s demand) — System Trade-offs', ...
            upper(fuel_name{f}), lvl),'FontSize',13,'FontWeight','bold');
        subplot(4,1,1); plot(ratio_range*100, wGW,'-s','LineWidth',2,'MarkerSize',7);
        grid on; ylabel(sprintf('%s [GW]', cfg.gen_name));
        title(sprintf('Required %s Capacity', cfg.gen_name)); xticklabels({});
        subplot(4,1,2); plot(ratio_range*100, eGW,'-s','LineWidth',2,'MarkerSize',7);
        grid on; ylabel('Electrolyser [GW]'); title('Required Electrolyser Capacity'); xticklabels({});
        subplot(4,1,3); plot(ratio_range*100, exc,'-s','LineWidth',2,'MarkerSize',7);
        grid on; ylabel('Export [GWh/yr]'); title('Excess Generation for Grid Sale'); xticklabels({});
        subplot(4,1,4); plot(ratio_range*100, tnk,'-ko','LineWidth',2,'MarkerSize',7,'MarkerFaceColor','k');
        grid on; ylabel('H_2 tank [t]'); title('Required H_2 Buffer Storage');
        xlabel(sprintf('Electrolyser capacity [%% of %s]', lower(cfg.gen_name)));
    end
end

function fn_plot_site_plans(R, lvl)
% Schematic hub layouts. Each asset is drawn as a square of the same area as
% its Layer 3 footprint, so the blocks are proportional but the arrangement
% carries no siting information.

    comp_colors = [
        0.20 0.63 0.17; 0.12 0.47 0.71; 0.89 0.47 0.13; 0.55 0.34 0.29;
        0.98 0.60 0.60; 0.74 0.74 0.74; 0.45 0.17 0.50; 0.99 0.88 0.10];

    cases(1).name   = sprintf('Option 1: Ammonia Import Hub (%s)', lvl);
    cases(1).labels = {'Fuel Storage','Ship Berths','Truck Station','Rail Spur'};
    cases(1).areas  = R.opt1_comp_c{1};
    cases(1).colors = comp_colors([1,2,3,4],:);

    cases(2).name   = sprintf('Option 1: Methanol Import Hub (%s)', lvl);
    cases(2).labels = {'Fuel Storage','Ship Berths','Truck Station','Rail Spur'};
    cases(2).areas  = R.opt1_comp_c{2};
    cases(2).colors = comp_colors([1,2,3,4],:);

    cases(3).name   = sprintf('Option 2: Ammonia Production Hub (%s)', lvl);
    cases(3).labels = {'Fuel Storage','Electrolyser','H_2 Spheres','Synthesis','DAC','Ship Berths'};
    cases(3).areas  = R.opt2_comp_c{1};
    cases(3).colors = comp_colors([1,5,6,7,8,2],:);

    cases(4).name   = sprintf('Option 2: Methanol Production Hub (%s)', lvl);
    cases(4).labels = {'Fuel Storage','Electrolyser','H_2 Spheres','Synthesis','DAC','Ship Berths'};
    cases(4).areas  = R.opt2_comp_c{2};
    cases(4).colors = comp_colors([1,5,6,7,8,2],:);

    for i = 1:4
        figure('Name', cases(i).name, 'Position',[50+i*20, 50+i*20, 1200, 450]);
        hold on; axis equal;
        cur_x = 0; gap = 50;
        for j = 1:numel(cases(i).areas)
            A_ha = cases(i).areas(j);
            % Each asset drawn as a square of equal area, so the blocks are
            % proportional. The arrangement carries no siting information.
            if A_ha > 0
                side = sqrt(A_ha*10000);
                rectangle('Position',[cur_x,0,side,side],'FaceColor',cases(i).colors(j,:), ...
                    'EdgeColor','k','LineWidth',1.5);
                text(cur_x+side/2, side/2, sprintf('%s\n%.2f ha', cases(i).labels{j}, A_ha), ...
                    'HorizontalAlignment','center','VerticalAlignment','middle', ...
                    'FontSize',10,'FontWeight','bold','BackgroundColor',[1 1 1 0.75],'Margin',2);
                cur_x = cur_x + side + gap;
            end
        end
        total = sum(cases(i).areas);
        title(sprintf('%s\nNet asset area: %.2f ha (blocks as proportional squares)', ...
            cases(i).name, total),'FontSize',13,'FontWeight','bold');
        xlabel('Physical Linear Distance [m]'); ylabel('Physical Linear Distance [m]');
        grid on; set(gca,'Layer','top');
        max_h = max(sqrt(cases(i).areas*10000));
        xlim([-gap, cur_x]); ylim([-gap, max_h+gap]);
    end
end

% -------------------------------------------------------------------------
% CORE MODEL FUNCTIONS
% -------------------------------------------------------------------------

function [n_row, n_col] = fn_grid(n_t)
% FN_GRID In-group rectangular arrangement, Eqs. 3.23-3.24. Rows are the integer
% square root of the group count, columns follow from what must be
% accommodated. Groups are capped at six, so this yields at most three columns
% and two rows, which are the six arrangements of Figure 3.3. It is a fixed
% layout convention, not an area optimisation.
    if n_t <= 0, n_row = 0; n_col = 0; return; end
    n_row = floor(sqrt(n_t));
    n_col = ceil(n_t / n_row);
end

function groups = fn_group_split(n_total, n_pg_max)
% FN_GROUP_SPLIT Allocation into containment groups, Eq. 3.22. Groups are
% filled to the six-tank insurer limit and the remainder forms the last group.
    if n_total <= 0, groups = 0; return; end
    % Fill groups to the cap and leave the remainder in the last one.
    n_grp = ceil(n_total / n_pg_max);
    groups = zeros(1, n_grp);
    rem_ = n_total;
    for i = 1:n_grp
        if rem_ >= n_pg_max
            groups(i) = n_pg_max; rem_ = rem_ - n_pg_max;
        else
            groups(i) = rem_; rem_ = 0;
        end
    end
end

function [n_tanks, v_req, V_geom] = fn_tank_split(v_working, eff, v_max)
% FN_TANK_SPLIT Tank count and per-tank volumes, Eqs. 3.12-3.16. The count is
% an integer, so the storage footprint steps rather than scales smoothly.
    % Round up to whole tanks, then redistribute the duty evenly so no tank
    % is a part load.
    v_geom_tot = v_working / eff;
    n_tanks = ceil(v_geom_tot / v_max);
    v_req   = v_working / n_tanks;
    V_geom  = v_req / eff;
end

function R = fn_rail_config(mass_rail_kg, n_trains_base, vol_per_cart, rho_carried, ...
    L_cart, L_train_max, policy, siding_factor, op_days, max_tpd)
% FN_RAIL_CONFIG Block-train configuration under the length cap, Eqs. 3.47-3.52.
%
% Wagon capacity is a usable VOLUME filled at the carried density, so the
% payload per car is vol_per_cart * rho_carried. For ammonia at 85 m3 and
% 602.8 kg/m3 this is 51.2 t, inside the 50-69 t range of Table B.7. The annual
% rail duty is passed as a MASS so the balance closes regardless of the state
% in which each mode transports the fuel.
%
% Train length is capped at 740 m. Where the baseline frequency would require
% a longer consignment the train is held at maximum length and the frequency
% is increased instead, and if the resulting arrival rate exceeds what one
% siding can turn round, parallel platforms are added.

    n_carts_max  = floor(L_train_max / L_cart);          % Eq. 3.47
    cart_payload = vol_per_cart * rho_carried;           % [kg per wagon]

    % No rail allocation means no siding, no trains and no platform, rather
    % than an empty service running at the baseline frequency.
    if mass_rail_kg <= 0
        R = struct('n_trains', 0, 'n_carts', 0, 'mass_per_train', 0, ...
            'cart_payload_t', cart_payload/1000, 'L_siding', 0, 'L_total', 0, ...
            'capped', false, 'trains_per_day', 0, 'n_platforms', 0);
        return
    end

    % Start from the reference frequency and see whether the consignment fits
    % inside the length limit. If not, hold the length and raise the frequency.
    n_trains = n_trains_base;
    mass_per_train = mass_rail_kg / n_trains;
    n_carts = ceil(mass_per_train / cart_payload);       % Eq. 3.48
    capped  = false;

    if n_carts > n_carts_max                             % Eq. 3.49
        capped = true;
        n_carts = n_carts_max;
        mass_per_train = n_carts * cart_payload;
        n_trains = ceil(mass_rail_kg / mass_per_train);
        % Re-spread the annual duty evenly over the resulting frequency, so
        % the last consignment is not a part load.
        mass_per_train = mass_rail_kg / n_trains;
    end

    switch policy                                        % Eq. 3.50
        case 'standard'
            L_siding = L_train_max;
        otherwise
            L_siding = n_carts * L_cart;
    end

    trains_per_day = n_trains / op_days;
    n_platforms = max(1, ceil(trains_per_day / max_tpd));  % Eq. 3.52

    R = struct('n_trains', n_trains, 'n_carts', n_carts, ...
        'mass_per_train', mass_per_train, ...
        'cart_payload_t', cart_payload/1000, ...
        'L_siding', L_siding, 'L_total', L_siding * siding_factor, ...
        'capped', capped, 'trains_per_day', trains_per_day, ...
        'n_platforms', n_platforms);
end

function [A1,W1,H1, A2,W2,H2, A3,W3,H3] = ...
    fn_three_layer(n_tanks, V_geom, V_farm, D_out, d_shell, d_btw, s_bldg, ...
    is_dwdi, n_pg_max, h_bund)
% FN_THREE_LAYER Three-layer spatial model, Section 3.6.1, Eqs. 3.22-3.37.
%   Layer 1  hardware bounding box of the tank array
%   Layer 2  secondary containment, equal to Layer 1 for DWDI ammonia
%   Layer 3  loss-prevention setback applied radially to Layer 1
% applies the 25% rule to the containment group, as the
% thesis states it; 'farm' applies it to the whole tank farm.

    grps  = fn_group_split(n_tanks, n_pg_max);           % Eq. 3.22
    n_grp = numel(grps);

    % Groups are laid side by side: widths add with a gap between them, and
    % the depth is the deepest single group.
    W1_total = 0; H1_max = 0;
    W2_total = 0; H2_max = 0;
    pitch = D_out + d_shell;                             % Eq. 3.25

    for i = 1:n_grp
        n_t = grps(i);
        [n_row, n_col] = fn_grid(n_t);                   % Eqs. 3.23-3.24
        W1_grp = (n_col-1)*pitch + D_out;                % Eqs. 3.26-3.27
        H1_grp = (n_row-1)*pitch + D_out;

        if is_dwdi
            % Integral secondary containment: Layer 2 coincides with Layer 1.
            W2_grp = W1_grp; H2_grp = H1_grp;
        else
            % Eq. 3.31. For n_t <= 4 the 110% single-tank rule always governs
            % on the group basis, since 0.25*n_t*V <= V < 1.10*V.
                V_liq_req = max(1.10*V_geom, 0.25*n_t*V_geom);
       
            % Eq. 3.32: bund floor area, corrected for the base area the tanks
            % displace, and never smaller than the hardware box it encloses.
            displaced = n_t * (pi/4 * D_out^2);
            A_bund = max(V_liq_req/h_bund + displaced, W1_grp*H1_grp);
            % Eqs. 3.33-3.34: dimensions at preserved aspect ratio.
            AR = W1_grp / H1_grp;
            W2_grp = sqrt(A_bund * AR);
            H2_grp = sqrt(A_bund / AR);
        end

        W1_total = W1_total + W1_grp; H1_max = max(H1_max, H1_grp);
        W2_total = W2_total + W2_grp; H2_max = max(H2_max, H2_grp);
    end

    if n_grp > 1                                         % Eq. 3.28
        W1_total = W1_total + (n_grp-1)*d_btw;
        W2_total = W2_total + (n_grp-1)*d_btw;
    end

    W1 = W1_total; H1 = H1_max; A1 = W1*H1;              % Eq. 3.30
    W2 = W2_total; H2 = H2_max; A2 = W2*H2;

    W3 = max(W1 + 2*s_bldg, W2);                         % Eqs. 3.35-3.36
    H3 = max(H1 + 2*s_bldg, H2);
    A3 = W3*H3;                                          % Eq. 3.37
end