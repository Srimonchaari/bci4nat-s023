% EEG comparison figures: hand (T1) vs. foot (T2) motor imagery, S023.
% Produces the Results 3.1 figures: ERD% at C3/Cz/C4 and topoplots of
% mu/beta band ERD%.
%
% ERD% (event-related desynchronisation) is used rather than raw power,
% since raw power is dominated by overall signal level per subject and
% does not reveal the task-related change:
%   ERD% = (baseline_power - imagery_power) / baseline_power * 100
%
% Known limitation: the pre-cue baseline window is short (0.5 s, 51
% samples at 100 Hz), which biases absolute ERD% magnitudes upward
% relative to published values. The relative hand-vs-foot comparison is
% still reliable; see the report's limitations discussion.
%
% Requirements: MATLAB + EEGLAB
% Input: S023_MI_preproc.set (epoched, ICA-cleaned). Epochs span
% [-0.5, 3.5] s, so [-0.5, 0] s is the baseline and [0.5, 3.5] s is the
% imagery analysis window.

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

% Defensive: remove BCILAB's uint64 override if it is still on the path
% from an earlier session (breaks figure rendering otherwise).
uint64ShadowDir = fullfile(projectroot, 'Toolboxes', 'BCILAB-devel', ...
    'dependencies', 'fileio-2014-06-22', '@uint64');
if exist(uint64ShadowDir, 'dir') && any(strcmp(strsplit(path, pathsep), uint64ShadowDir))
    rmpath(uint64ShadowDir);
    rehash;
end

% 2) Labels from epoch event types (T1 = hand, T2 = foot)
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

% 4) Spectra for baseline and imagery windows, per condition.
% winsize is explicitly matched to the baseline window length (51
% samples) for all four calls: spectopo's default winsize (= srate)
% otherwise exceeds the short baseline window and inflates ERD% to an
% implausible ~90-100% everywhere. Matched windows also share one
% frequency grid, so no interpolation is needed.
winSamples = nBase;
[handBaseSpec, freqsBase] = spectopo(EEG.data(:, baseIdx, handIdx), nBase, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[footBaseSpec, ~]         = spectopo(EEG.data(:, baseIdx, footIdx), nBase, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[handImagSpec, freqsImag] = spectopo(EEG.data(:, imagIdx, handIdx), nImag, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
[footImagSpec, ~]         = spectopo(EEG.data(:, imagIdx, footIdx), nImag, EEG.srate, ...
    'winsize', winSamples, 'plot','off');
freqs = freqsImag;
if ~isequal(freqsBase, freqsImag)
    % Defensive fallback: interpolate onto a common grid if they ever diverge
    handBaseSpec = interp1(freqsBase, handBaseSpec', freqsImag, 'linear', 'extrap')';
    footBaseSpec = interp1(freqsBase, footBaseSpec', freqsImag, 'linear', 'extrap')';
end

% Spectra are in dB; convert to linear power before computing ERD%,
% since percent-change is only meaningful on the linear scale.
handBaseLin = 10.^(handBaseSpec/10);
footBaseLin = 10.^(footBaseSpec/10);
handImagLin = 10.^(handImagSpec/10);
footImagLin = 10.^(footImagSpec/10);

handERD = 100 * (handBaseLin - handImagLin) ./ handBaseLin;  % [nbchan x nfreq], %
footERD = 100 * (footBaseLin - footImagLin) ./ footBaseLin;

% -----------------------------------------------------------------
% Figure 1: ERD% comparison at C3, Cz, C4 (hand vs. foot)
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

% Mu-band-averaged ERD% at Cz, pooled over the full imagery window --
% the number the report text quotes ("around 78%/54%"). Printed here
% since the report text was originally written by eyeballing the plot
% and needs an exact, checkable figure instead.
czIdx0 = chanIdx(strcmpi(chansOfInterest, 'Cz'));
muIdx0 = freqs >= 8 & freqs <= 13;
fprintf('Full-window mu-band ERD%% at Cz, hand: %.1f %%\n', mean(handERD(czIdx0, muIdx0)));
fprintf('Full-window mu-band ERD%% at Cz, foot: %.1f %%\n', mean(footERD(czIdx0, muIdx0)));

% Text/axes color explicitly forced to black: MATLAB's dark-mode UI
% theme otherwise makes titles/labels render as light grey, which reads
% fine on screen but is washed out and hard to read once saved to PNG.
fig1 = figure('Name','ERD Comparison','Color','w','Position',[100 100 1200 400]);
set(fig1,'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k', ...
    'defaultAxesColor','w');
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
    % defaultAxesColor above does not reliably reach every axes type in
    % this MATLAB/EEGLAB combination (seen previously with spectopo);
    % force it explicitly per-axes too.
    set(gca,'Color','w');
end
sgt1 = sgtitle('ERD%: hand vs. foot motor imagery (S023), relative to pre-cue baseline; mu (8-13 Hz) and beta (13-30 Hz) marked');
sgt1.Color = 'k';
clean_save(gcf, fullfile(results_dir, 'S023_spectrum_comparison.png'));

% -----------------------------------------------------------------
% Figure 2: Topoplot comparison of mu (8-13 Hz) and beta (13-30 Hz) ERD%
% for hand vs. foot conditions
% -----------------------------------------------------------------
bands = struct('name', {'Mu (8-13 Hz)', 'Beta (13-30 Hz)'}, 'range', {[8 13], [13 30]});

% All four band-averaged maps are computed first so one shared color
% scale (clim) can be applied across every subplot. Per-subplot
% auto-scaling would otherwise span far beyond the real data range,
% since ERD% values here cluster tightly, making the maps look
% uniformly dark and hiding the hand/foot difference.
allVals = cell(numel(bands), 2);
for b = 1:numel(bands)
    fidx = freqs >= bands(b).range(1) & freqs <= bands(b).range(2);
    allVals{b,1} = mean(handERD(:,fidx), 2);
    allVals{b,2} = mean(footERD(:,fidx), 2);
end
allValsFlat = cat(1, allVals{:});
climRange = [min(allValsFlat) max(allValsFlat)];

% Text color forced to black for the same dark-mode reason as above.
% Height of 650px (restored from an earlier 520px attempt that was too
% short for a 2x2 topoplot grid plus a wrapped sgtitle -- the sgtitle
% ended up overlapping the top-row subplot titles at 520px).
fig2 = figure('Name','Band ERD Topography Comparison','Color','w','Position',[100 100 900 650]);
set(fig2,'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k', ...
    'defaultAxesColor','w');
% Axes are placed at explicit positions with headroom reserved at the
% top for sgtitle, rather than via subplot(2,2,.) followed by resizing
% an existing axes -- an earlier attempt that repositioned subplot(2,2,.)
% axes after creation fixed the sgtitle overlap but re-triggered the
% axes-toolbar rendering artifact clean_save exists to prevent (a stray
% diagonal line baked into the saved PNG), and a second
% disableDefaultInteractivity call after the resize did not stop it.
% Creating axes at their final position from the start avoids that.
axPositions = [0.08 0.50 0.38 0.38; 0.54 0.50 0.38 0.38; ...
               0.08 0.05 0.38 0.38; 0.54 0.05 0.38 0.38];
plotIdx = 1;
for b = 1:numel(bands)
    for cond = 1:2
        if cond == 1
            bandERDvals = allVals{b,1}; condName = 'Hand (T1)';
        else
            bandERDvals = allVals{b,2}; condName = 'Foot (T2)';
        end
        axes('Position', axPositions(plotIdx,:)); %#ok<LAXES>
        topoplot(bandERDvals, EEG.chanlocs, 'electrodes','off');
        clim(climRange);
        colorbar;
        title(sprintf('%s - %s', bands(b).name, condName));
        set(gca,'Color','w');
        plotIdx = plotIdx + 1;
    end
end
colormap(parula);
sgt2 = sgtitle('Band ERD% topography: hand vs. foot motor imagery (S023)', 'FontSize', 12);
sgt2.Color = 'k';
clean_save(gcf, fullfile(results_dir, 'S023_topo_comparison.png'));

% -----------------------------------------------------------------
% Figure 3: Time-resolved mu-band ERD% at Cz across the imagery period
% -----------------------------------------------------------------
% Figures 1-2 pool ERD% over the whole 0.5-3.5s imagery window, so they
% cannot show WHEN within that window the hand/foot difference is
% strongest. This splits the window into three ~1s sub-windows (early,
% mid, late) and repeats the same baseline-relative ERD% computation
% for each, using the same matched-winsize approach as above to avoid
% the earlier windowing bias.
subWindows = struct('name', {'Early (0.5-1.5s)', 'Mid (1.5-2.5s)', 'Late (2.5-3.5s)'}, ...
    'range', {[500 1500], [1500 2500], [2500 3500]});
czIdx = chanIdx(strcmpi(chansOfInterest, 'Cz'));
muRange = [8 13];

handMuERD_time = zeros(1, numel(subWindows));
footMuERD_time = zeros(1, numel(subWindows));
for w = 1:numel(subWindows)
    subIdx = EEG.times >= subWindows(w).range(1) & EEG.times <= subWindows(w).range(2);
    nSub = sum(subIdx);
    % winsize matched to the shorter of baseline/sub-window length, for
    % the same reason as above: mismatched windows bias ERD% upward.
    subWin = min(nSub, nBase);
    [handSubSpec, subFreqs] = spectopo(EEG.data(czIdx, subIdx, handIdx), nSub, EEG.srate, ...
        'winsize', subWin, 'plot','off');
    [footSubSpec, ~]        = spectopo(EEG.data(czIdx, subIdx, footIdx), nSub, EEG.srate, ...
        'winsize', subWin, 'plot','off');
    [handBaseSubSpec, baseSubFreqs] = spectopo(EEG.data(czIdx, baseIdx, handIdx), nBase, EEG.srate, ...
        'winsize', subWin, 'plot','off');
    [footBaseSubSpec, ~]            = spectopo(EEG.data(czIdx, baseIdx, footIdx), nBase, EEG.srate, ...
        'winsize', subWin, 'plot','off');
    if ~isequal(baseSubFreqs, subFreqs)
        handBaseSubSpec = interp1(baseSubFreqs, handBaseSubSpec', subFreqs, 'linear', 'extrap')';
        footBaseSubSpec = interp1(baseSubFreqs, footBaseSubSpec', subFreqs, 'linear', 'extrap')';
    end
    fidxSub = subFreqs >= muRange(1) & subFreqs <= muRange(2);
    handSubLin = 10.^(handSubSpec/10); footSubLin = 10.^(footSubSpec/10);
    handBaseSubLin = 10.^(handBaseSubSpec/10); footBaseSubLin = 10.^(footBaseSubSpec/10);
    handMuERD_time(w) = mean(100 * (handBaseSubLin(fidxSub) - handSubLin(fidxSub)) ./ handBaseSubLin(fidxSub));
    footMuERD_time(w) = mean(100 * (footBaseSubLin(fidxSub) - footSubLin(fidxSub)) ./ footBaseSubLin(fidxSub));
end

fig3 = figure('Name','Time-resolved mu ERD at Cz','Color','w','Position',[100 100 700 380]);
set(fig3,'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k', ...
    'defaultAxesColor','w');
bar([handMuERD_time; footMuERD_time]');
set(gca, 'XTickLabel', {subWindows.name}, 'XColor','k', 'YColor','k', 'Color','w');
ylabel('Mu-band ERD (%) at Cz', 'Color','k');
legend({'Hand (T1)','Foot (T2)'}, 'Location','best');
title('Mu-band ERD% at Cz across the imagery period (S023)', 'Color','k');
grid on;
clean_save(gcf, fullfile(results_dir, 'S023_time_resolved_ERD.png'));
fprintf('Time-resolved mu ERD at Cz, hand: %.1f / %.1f / %.1f %%\n', handMuERD_time);
fprintf('Time-resolved mu ERD at Cz, foot: %.1f / %.1f / %.1f %%\n', footMuERD_time);

function clean_save(figHandle, outPath)
% Some saved figures showed a stray diagonal line and black "..." boxes
% baked into the PNG: MATLAB's live figure-interaction UI (axes
% toolbar, resize handles) getting captured mid-render by saveas,
% triggered by the known uint64 graphics-interaction bug corrupting the
% UI state at save time. Disabling axes interactivity and forcing a
% full render before saveas prevents that overlay from being captured.
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
