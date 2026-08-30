% EEGLAB preprocessing for S023 hand vs. foot motor imagery.
% Requirements: MATLAB + EEGLAB
% Output: cleaned continuous set (for submission) and cleaned epoched set
% (for analysis/classification).

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

% 4) Band-pass 7-30 Hz to keep mu/beta rhythms, plus 50 Hz notch for line noise
EEG = pop_eegfiltnew(EEG, 7, 30);
EEG = pop_eegfiltnew(EEG, 48, 52, [], 1);
EEG.setname = 'S023_filt';

% 5) Resample to 100 Hz (nothing of interest above 30 Hz for this task)
EEG = pop_resample(EEG, 100);
EEG.setname = 'S023_rs100';

% 6) ICA (extended infomax) on continuous, filtered data, before epoching
% rndreset off: runica's default re-seeds its random weight
% initialization from the clock on every call, so component
% ordering/shape (and everything downstream: which ICs get removed,
% what BCILAB trains on, final accuracy) changed on every rerun even
% with the classifier-side seed fixed. Off falls back to a fixed
% rand('state',0), making the decomposition reproducible run to run.
EEG = pop_runica(EEG, 'icatype', 'runica', 'extended', 1, 'rndreset', 'off');
EEG.setname = 'S023_ica';

% Component inspection (topography, time course, spectrum via pop_prop).
% Pre-ICA band-pass compresses every component's spectrum into the same
% 7-30 Hz shape, so topography and time-course transients are the main
% criteria, cross-checked below against each component's actual
% within-band spectral shape (where power concentrates inside 7-30 Hz).
compsOfInterest = [6 15 1 4];
if isempty(EEG.icaact)
    EEG.icaact = eeg_getdatact(EEG, 'component', 1:size(EEG.icaweights,1));
end
% Figure sized larger than default, and each subplot's y-label shortened
% after spectopo draws it, because spectopo's default long y-axis label
% ("Power Spectral Density 10*log10(uV^2/Hz)") collided with the
% neighboring subplot in a tight 2x2 grid at default figure size.
% Height reduced from 800px (was taller than the content needed at this
% width); text color forced to black for the same dark-mode reason noted
% throughout this pipeline (default axes/title color otherwise renders
% as light, hard-to-read grey once saved to PNG).
figIC = figure('Name','IC spectra (within 7-30 Hz band)','Color','w','Position',[100 100 1100 650]);
set(figIC,'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k', ...
    'defaultAxesColor','w');
for i = 1:numel(compsOfInterest)
    ic = compsOfInterest(i);
    subplot(2,2,i);
    spectopo(EEG.icaact(ic,:,:), 0, EEG.srate, 'freqrange', [7 30], 'plot','on');
    title(sprintf('IC%d', ic), 'Color','k');
    ylabel('PSD (dB)', 'Color','k');
    % spectopo sets its axes background to black directly (not just via
    % the dark-mode default), so the defaultAxesColor property above
    % doesn't reach it -- force it back to white per-axes after spectopo
    % draws.
    set(gca,'XColor','k','YColor','k','Color','w');
end
sgt = sgtitle('Within-band (7-30 Hz) power spectrum of the four inspected components');
sgt.FontSize = 11;
sgt.Color = 'k';
clean_save(gcf, fullfile(outpath, '..', 'Results&Figures', 'S023_IC_spectra.png'));

% Removed (artifact-like):
%   IC6, IC15 - sharp focal topography over left temporal area; time
%   course shows spike-like transients typical of muscle (EMG) activity.
% Kept (brain-like):
%   IC1 - smooth posterior topography, ~10 Hz peak (posterior alpha),
%   waxing-and-waning time course.
%   IC4 - smooth central/sensorimotor topography, no spike-like transients.
compsToRemove = [6 15];
EEG = pop_subcomp(EEG, compsToRemove, 0);
EEG.setname = 'S023_ica_cleaned';

% 7) Save the cleaned CONTINUOUS dataset (before epoching), required for submission
EEG = pop_saveset(EEG, 'filename', 'S023_cleaned_continuous.set', 'filepath', outpath);
fprintf('Saved cleaned continuous dataset: %s\n', fullfile(outpath, 'S023_cleaned_continuous.set'));

% 8) Epoch around cues, then baseline-correct.
% Window is [-0.5, 3.5] s: covers the pre-cue baseline and the full
% imagery period in one epoch. Do not crop epochs further with
% pop_select after this; it corrupts event-type metadata on
% already-epoched data. The [0.5, 3.5] s analysis sub-window is taken
% as a plain array slice later instead.
markers = {'T1','T2'};                   % <-- EDIT if your labels differ
EEG = pop_epoch(EEG, markers, [-0.5 3.5], 'epochinfo','yes');
EEG = pop_rmbase(EEG, [-500 0]);
EEG.setname = 'S023_final';

% 9) Save preprocessed, epoched dataset (for the classification script)
EEG = pop_saveset(EEG, 'filename', outfile, 'filepath', outpath);
fprintf('Saved: %s\n', fullfile(outpath, outfile));

function clean_save(figHandle, outPath)
% The saved IC-spectra PNG previously showed a stray diagonal line and
% black "..." boxes: MATLAB's live figure-interaction UI (axes toolbar,
% resize handles) getting captured mid-render by saveas, triggered by
% the known uint64 graphics-interaction bug corrupting the UI state at
% save time. Disabling axes interactivity and forcing a full render
% before saveas prevents that overlay from being captured.
axesHandles = findall(figHandle, 'Type', 'axes');
for ax = 1:numel(axesHandles)
    try
        disableDefaultInteractivity(axesHandles(ax));
    catch
    end
end
drawnow;
saveas(figHandle, outPath);
fprintf('Saved: %s\n', outPath);
end
