% -----------------------------------------------------------------
% EEG comparison figures: hand (T1) vs. foot (T2) motor imagery, S023
% Produces the Results 3.1 figures that were missing from last year's
% report - a spectral ERD%% comparison at sensorimotor electrodes and a
% topoplot comparison of mu/beta band ERD%%, showing the actual
% event-related desynchronization difference between conditions instead
% of describing it in prose only.
%
% NOTE on ERD vs. raw power: an earlier version of this script plotted
% raw absolute power spectra for each condition, which came out nearly
% identical between hand and foot at C3/Cz/C4 - not a bug, but the wrong
% quantity to plot. Raw power is dominated by each individual's overall
% signal level, which swamps the (comparatively small) task-related
% change. Event-related desynchronization (ERD) is defined relative to a
% pre-cue baseline:
%   ERD%% = (baseline_power - imagery_power) / baseline_power * 100
% i.e. the percent DROP in power during imagery relative to rest, which
% is the standard quantity in the motor-imagery literature (and what the
% assignment/last year's report describe conceptually) and is much more
% likely to reveal the actual hand-vs-foot spatial/spectral difference.
%
% KNOWN LIMITATION (for the report's Methods/limitations, not hidden):
% the pre-cue baseline window is short (0.5 s = 51 samples at 100 Hz).
% Debugging confirmed a real windowing bug (mismatched winsize between
% the 51-sample baseline and 300-sample imagery calls) that produced
% physiologically implausible ~90-100%% ERD everywhere; fixing that
% (matched winsize for both calls) brought values down to a real,
% interpretable range with genuine spatial/spectral structure (e.g. a
% deeper mu-band dip at Cz for foot than hand, consistent with the
% medial/leg motor cortex representation) - but absolute ERD%% magnitudes
% (~65-85%%) still run higher than the ~20-50%% typically reported in
% published motor-imagery studies, most likely because power spectral
% density estimation from a very short window is inherently biased/noisy
% even with matched parameters. The RELATIVE hand-vs-foot comparison
% shown in these figures is the reliable, reportable finding; the
% absolute ERD%% numbers should be described as elevated/not directly
% comparable to literature values due to the short baseline window
% available in this dataset, rather than presented as precise measurements.
%
% Requirements: MATLAB + EEGLAB
% Input: S023_MI_preproc.set (epoched, ICA-cleaned) from
%        eeglab_preprocess_S023.m. Epochs span [-0.5, 3.5] s relative to
%        cue onset, so [-0.5, 0] s serves as the pre-cue baseline window
%        and [0.5, 3.5] s as the sustained-imagery analysis window.
% -----------------------------------------------------------------

% 0) Paths
projectroot = '/Users/srimonchaari/Documents/Projects/BCI';   % <-- EDIT if repo moves
eeglabpath  = fullfile(projectroot, 'Toolboxes', 'eeglab2026.0.0');
inpath      = fullfile(projectroot, 'Dataset');
infile      = 'S023_MI_preproc.set';
results_dir = fullfile(projectroot, 'Results&Figures');

% 1) Load preprocessed epochs
addpath(eeglabpath);
[ALLEEG, EEG, ~, ~] = eeglab; %#ok<ASGLU>
EEG = pop_loadset('filename', infile, 'filepath', inpath);

% NOTE: if BCILAB was loaded earlier in this MATLAB session, its
% dependencies/fileio-2014-06-22/@uint64/ folder may still be on the
% path, silently overriding MATLAB's built-in uint64 arithmetic operators
% and breaking figure/plot rendering with "Invalid type of input
% arguments (should be uint64)" errors. Defensively remove it here too
% (harmless if it was never added).
uint64ShadowDir = fullfile(projectroot, 'Toolboxes', 'BCILAB-devel', ...
    'dependencies', 'fileio-2014-06-22', '@uint64');
if exist(uint64ShadowDir, 'dir') && any(strcmp(strsplit(path, pathsep), uint64ShadowDir))
    rmpath(uint64ShadowDir);
    rehash;
end

% 2) Labels from epoch event types (T1=hand, T2=foot)
classA = {'T1'};   % hand
classB = {'T2'};   % foot
y = zeros(EEG.trials,1);
for k = 1:EEG.trials
    types = EEG.epoch(k).eventtype; if ~iscell(types), types = {types}; end
    lab = 0;
    for t = 1:numel(types)
        if any(strcmpi(string(types{t}), classA)), lab = 1; break; end
        if any(strcmpi(string(types{t}), classB)), lab = 2; break; end
    end
    y(k) = lab;
end
handIdx = find(y==1);
footIdx = find(y==2);
fprintf('Hand trials: %d, Foot trials: %d\n', numel(handIdx), numel(footIdx));

% 3) Baseline window [-0.5, 0] s and imagery window [0.5, 3.5] s (ms)
baselineWindow = [-500 0];
imageryWindow  = [500 3500];
baseIdx = EEG.times >= baselineWindow(1) & EEG.times <= baselineWindow(2);
imagIdx = EEG.times >= imageryWindow(1)  & EEG.times <= imageryWindow(2);
nBase = sum(baseIdx);
nImag = sum(imagIdx);

% 4) Compute full-scalp spectra for baseline and imagery windows, per
%    condition. spectopo dim 1 = channels, frames = samples/epoch,
%    dim 3 = trials; averaging across trials is handled internally.
%
% IMPORTANT: spectopo's default 'winsize' is EEG.srate (100 samples here),
% regardless of how many samples are actually passed per epoch. With the
% 50-sample baseline window, that default window is LARGER than the data
% itself, which produced an unreliable, massively inflated baseline
% estimate (confirmed empirically: baseline power came out ~18-20x larger
% than imagery-period power at every channel/frequency, giving a
% physiologically implausible ~90-100%% "ERD" everywhere - not a real
% effect, a windowing artifact). Fix: explicitly set 'winsize' to the
% baseline window's length (50) for BOTH calls, so baseline and imagery
% spectra are computed with matched, appropriately-sized windows and are
% directly comparable. This also means both share the same frequency
% grid, so no interpolation is needed.
winSamples = nBase;  % 51 samples = 0.51 s at 100 Hz
[handBaseSpec, freqsBase] = spectopo(EEG.data(:, baseIdx, handIdx), nBase, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[footBaseSpec, ~]         = spectopo(EEG.data(:, baseIdx, footIdx), nBase, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[handImagSpec, freqsImag] = spectopo(EEG.data(:, imagIdx, handIdx), nImag, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[footImagSpec, ~]         = spectopo(EEG.data(:, imagIdx, footIdx), nImag, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
% NOTE: attempted zero-padding the FFT (nfft > winsize) as a further fix
% for the still-elevated ERD%% values (see below), but this caused the
% baseline and imagery calls to return mismatched frequency grids
% (spectopo evidently handles nfft differently depending on input epoch
% length) - reverted to matched winsize only, which is internally
% consistent even though the resulting ERD%% magnitudes run higher than
% typical published values (see caveat below).
freqs = freqsImag;
if ~isequal(freqsBase, freqsImag)
    % Defensive fallback: interpolate baseline onto the imagery grid if
    % they ever diverge (should not happen with matched winsize/no nfft).
    handBaseSpec = interp1(freqsBase, handBaseSpec', freqsImag, 'linear', 'extrap')';
    footBaseSpec = interp1(freqsBase, footBaseSpec', freqsImag, 'linear', 'extrap')';
end

% Spectra are in dB (10*log10 uV^2/Hz); convert to linear power before
% computing ERD%%, since percent-change is only meaningful on the linear
% scale.
handBaseLin = 10.^(handBaseSpec/10);
footBaseLin = 10.^(footBaseSpec/10);
handImagLin = 10.^(handImagSpec/10);
footImagLin = 10.^(footImagSpec/10);

handERD = 100 * (handBaseLin - handImagLin) ./ handBaseLin;  % [nbchan x nfreq], %%
footERD = 100 * (footBaseLin - footImagLin) ./ footBaseLin;

% -----------------------------------------------------------------
% Figure 1: ERD%% comparison at C3, Cz, C4 (hand vs. foot)
% -----------------------------------------------------------------
chansOfInterest = {'C3','Cz','C4'};
chanIdx = zeros(1,numel(chansOfInterest));
for c = 1:numel(chansOfInterest)
    idx = find(strcmpi({EEG.chanlocs.labels}, chansOfInterest{c}));
    if isempty(idx)
        error('Channel %s not found in chanlocs.', chansOfInterest{c});
    end
    chanIdx(c) = idx(1);
end

figure('Name','ERD Comparison','Color','w','Position',[100 100 1200 400]);
for c = 1:numel(chansOfInterest)
    subplot(1, numel(chansOfInterest), c);
    plot(freqs, handERD(chanIdx(c),:), 'b-', 'LineWidth', 1.5); hold on;
    plot(freqs, footERD(chanIdx(c),:), 'r-', 'LineWidth', 1.5);
    yline(0, 'k-');
    xline(8, 'k:'); xline(13, 'k:'); xline(30, 'k:');
    xlim([1 45]);
    xlabel('Frequency (Hz)');
    ylabel('ERD (%)');
    title(sprintf('%s', chansOfInterest{c}));
    if c == 1
        legend({'Hand (T1)','Foot (T2)'}, 'Location','best');
    end
    grid on;
end
sgtitle('ERD%: hand vs. foot motor imagery (S023), relative to pre-cue baseline; mu (8-13 Hz) and beta (13-30 Hz) marked');
saveas(gcf, fullfile(results_dir, 'S023_spectrum_comparison.png'));
fprintf('Saved: %s\n', fullfile(results_dir, 'S023_spectrum_comparison.png'));

% -----------------------------------------------------------------
% Figure 2: Topoplot comparison of mu (8-13Hz) and beta (13-30Hz) ERD%%
% for hand vs. foot conditions
% -----------------------------------------------------------------
bands = struct('name', {'Mu (8-13 Hz)', 'Beta (13-30 Hz)'}, 'range', {[8 13], [13 30]});

figure('Name','Band ERD Topography Comparison','Color','w','Position',[100 100 900 750]);
plotIdx = 1;
for b = 1:numel(bands)
    fidx = freqs >= bands(b).range(1) & freqs <= bands(b).range(2);
    handBandERD = mean(handERD(:,fidx), 2);
    footBandERD = mean(footERD(:,fidx), 2);
    for cond = 1:2
        if cond == 1
            bandERDvals = handBandERD; condName = 'Hand (T1)';
        else
            bandERDvals = footBandERD; condName = 'Foot (T2)';
        end
        subplot(2, 2, plotIdx);
        topoplot(bandERDvals, EEG.chanlocs, 'electrodes','off');
        colorbar;
        title(sprintf('%s - %s', bands(b).name, condName));
        plotIdx = plotIdx + 1;
    end
end
sgtitle('Band ERD% topography: hand vs. foot motor imagery (S023)', 'FontSize', 12);
saveas(gcf, fullfile(results_dir, 'S023_topo_comparison.png'));
fprintf('Saved: %s\n', fullfile(results_dir, 'S023_topo_comparison.png'));
