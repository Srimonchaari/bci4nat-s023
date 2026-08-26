% -------------------------------------------------------------
% EEGLAB PREPROCESSING - S023 hand vs foot motor imagery
% -------------------------------------------------------------
% Requirements: MATLAB + EEGLAB
% Edits: set 'projectroot' below if this repo is moved; confirm your event
%        markers (e.g., {'T1','T2'}) match the loaded dataset
% Output: S023_MI_preproc.set (epochs 0.5-3.5 s, 7-30 Hz, avg ref, 100 Hz)
% -------------------------------------------------------------

% 0) Paths
projectroot = '/Users/srimonchaari/Documents/Projects/BCI';   % <-- EDIT if repo moves
eeglabpath  = fullfile(projectroot, 'Toolboxes', 'eeglab2026.0.0');
inpath      = fullfile(projectroot, 'Dataset');
infile      = 'S023_hand_vs_foot.set';
outpath     = fullfile(projectroot, 'Dataset');
outfile     = 'S023_MI_preproc.set';

% 1) Start EEGLAB
addpath(eeglabpath);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab; %#ok<ASGLU,NASGU>

% 2) Load dataset
EEG = pop_loadset('filename', infile, 'filepath', inpath);
[ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG, 1); %#ok<ASGLU,NASGU>

% 3) Average reference
EEG = pop_reref(EEG, [], 'keepref','on');
EEG.setname = 'S023_avgref';

% 4) Band-pass 7-30 Hz (FIR) + optional 50 Hz notch
EEG = pop_eegfiltnew(EEG, 7, 30);         % passband
EEG = pop_eegfiltnew(EEG, 48, 52, [], 1); % notch (optional)
EEG.setname = 'S023_filt';

% 5) Resample to 100 Hz
EEG = pop_resample(EEG, 100);
EEG.setname = 'S023_rs100';

% 6) ICA decomposition (on continuous, cleaned data, before epoching)
EEG = pop_runica(EEG, 'icatype', 'runica', 'extended', 1);
EEG.setname = 'S023_ica';

% --- Component inspection (done via pop_selectcomps / pop_prop) ---
% Note: the 7-30 Hz band-pass applied before ICA compresses every
% component's power spectrum into the same passband shape, so spectral
% shape alone cannot discriminate artifact vs. brain components here -
% topography (focal/edge-localized vs. smooth/diffuse) was the primary
% criterion, cross-checked against the trial time series for spike-like
% transients.
%
% Removed (artifact, non-brain):
%   IC6  - sharp, isolated focal dipole at the left temporal/ear-adjacent
%          region, clearly separated from the smooth diffuse background;
%          consistent with muscle (EMG) or electrode-contact artifact.
%          Time course: sharp, spike-like transients rather than smooth
%          continuous oscillation.
%   IC15 - same pattern: small, sharply-bounded left temporal/parietal
%          focal blob distinct from broader diffuse topography. Time
%          course: same spike-like transient pattern as IC6.
% Kept (brain-like):
%   IC1 - smooth, broad posterior/occipital topography with a clear
%         ~10 Hz spectral peak, consistent with posterior alpha rhythm.
%         Time course: waxing-and-waning oscillatory activity typical of
%         an alpha rhythm, no spike-like transients.
%   IC4 - smooth, central/centro-parietal focus, anatomically plausible
%         location for sensorimotor cortex, coherent (non-fragmented)
%         topography. Time course: free of spike-like transients seen in
%         IC6/IC15.
compsToRemove = [6 15];
EEG = pop_subcomp(EEG, compsToRemove, 0);
EEG.setname = 'S023_ica_cleaned';

% 7) Save the cleaned CONTINUOUS dataset (before epoching) for submission
EEG = pop_saveset(EEG, 'filename', 'S023_cleaned_continuous.set', 'filepath', outpath);
fprintf('Saved cleaned continuous dataset: %s\n', fullfile(outpath, 'S023_cleaned_continuous.set'));

% 8) Epoch around cues (hand vs foot), then baseline-correct.
%    Epoch window is [-0.5, 3.5] s so it includes both the pre-cue
%    baseline period and the full post-cue analysis window in one epoch.
%    Do NOT follow this with pop_select(...,'time',...) to crop further -
%    on already-epoched data that call corrupts each epoch's event-type
%    metadata (verified: it silently relabels/loses trials, confirmed by
%    testing T1=23/T2=22 before the crop vs T1=1/T2=0 after). The
%    [0.5, 3.5] s "sustained imagery" sub-window used for analysis is
%    taken as a plain array slice on EEG.data in the classification
%    script instead, which is unaffected by this issue.
markers = {'T1','T2'};                   % <-- EDIT if your labels differ
EEG = pop_epoch(EEG, markers, [-0.5 3.5], 'epochinfo','yes');
EEG = pop_rmbase(EEG, [-500 0]);
EEG.setname = 'S023_final';

% 9) Save preprocessed, epoched dataset (for the classification script)
EEG = pop_saveset(EEG, 'filename', outfile, 'filepath', outpath);
fprintf('Saved: %s\n', fullfile(outpath, outfile));
