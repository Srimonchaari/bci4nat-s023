% BCILAB CSP+LDA classifier for S023 hand vs. foot motor imagery.
% Requirements: BCILAB on path; EEGLAB; preprocessed set available.
% Input: S023_cleaned_continuous.set (continuous, ICA-cleaned, not yet
% epoched). BCILAB does its own epoching here, so this must NOT be fed
% the already-epoched set.

projectroot = '/Users/srimonchaari/Documents/Projects/BCI';   % <-- EDIT if repo moves
addpath(fullfile(projectroot, 'Toolboxes', 'eeglab2026.0.0'));
addpath(fullfile(projectroot, 'Toolboxes', 'BCILAB-devel'));
% Startup output is captured and discarded; it is cosmetic plugin noise
% from BCILAB's vendored legacy EEGLAB copy, unrelated to this pipeline.
evalc('eeglab; bcilab;');

% BCILAB's fileio uint64 override conflicts with MATLAB's own graphics
% code and breaks figure rendering after startup; remove it once loaded.
uint64ShadowDir = fullfile(projectroot, 'Toolboxes', 'BCILAB-devel', ...
    'dependencies', 'fileio-2014-06-22', '@uint64');
if exist(uint64ShadowDir, 'dir') && any(strcmp(strsplit(path, pathsep), uint64ShadowDir))
    rmpath(uint64ShadowDir);
    rehash;
end

datapath = fullfile(projectroot, 'Dataset');
datafile = fullfile(datapath,'S023_cleaned_continuous.set');

% Load dataset into BCILAB
lastdata = io_loadset(datafile);

% Approach: CSP (3 pattern pairs) + LDA. Only EpochExtraction runs here;
% reference/filter/resample/ICA were already done in the EEGLAB script.
% FIRFilter and Resampling are explicitly disabled: ParadigmCSP applies
% its own defaults for both otherwise, silently re-processing data that
% is already filtered and resampled.
approach = {'CSP', ...
    'SignalProcessing', {'FIRFilter','off', 'Resampling','off', 'EpochExtraction',[0.5 3.5]}, ...
    'Prediction', {'FeatureExtraction', {'PatternPairs', 3}, ...
                    'MachineLearning', {'Learner', 'lda'}}};

% Calibrate with 5-fold CV. bci_train returns [measure, model, stats].
%
% EvaluationScheme is passed as an explicit, pre-computed list of
% {train_inds, test_inds} pairs rather than the plain fold-count "5".
% Reason: BCILAB's own fold-index generator (utl_crossval's
% make_indices) is supposed to be seeded (RepeatableResults defaults to
% 1, using a private RandStream), but bci_train never exposes that
% option to the caller, and four consecutive runs of this exact script
% produced four different confusion matrices. Building the split
% ourselves with a plain seeded randperm() removes BCILAB's fold-RNG
% from the picture entirely and is independently checkable.
% lastdata (from io_loadset) does not expose a plain top-level .event
% field the way a standard EEGLAB EEG struct does, so the trial count is
% read via a direct pop_loadset call instead (same file, same events).
targetMarkers = {'T1','T2'};
EEGforCount = pop_loadset('filename', 'S023_cleaned_continuous.set', 'filepath', datapath);
markerTypes = {EEGforCount.event.type};
trialMask = ismember(markerTypes, targetMarkers);
nTrials = sum(trialMask);
kFolds = 5;
% Seeded immediately before use, not at the top of the script: eeglab;
% bcilab; startup code runs in between and evidently reseeds/consumes
% MATLAB's global RNG somewhere internally (plugin discovery, cache
% tags, temp names, etc.), which was silently clobbering an
% earlier-set rng(1,'twister') before this randperm ever ran -- the
% likely explanation for why the "seeded" split still changed on every
% run despite the seed call being present in the script.
rng(1, 'twister');
foldPerm = randperm(nTrials);
cvScheme = cell(1, kFolds);
for f = 0:kFolds-1
    testIdx = sort(foldPerm(1 + floor(f*nTrials/kFolds) : floor((f+1)*nTrials/kFolds)));
    trainIdx = sort(setdiff(1:nTrials, testIdx));
    cvScheme{f+1} = {trainIdx, testIdx};
end
% Diagnostic: print the actual computed split so we can directly check,
% from console output alone, whether this part is identical run to run
% (isolating whether the remaining non-determinism is in this split or
% somewhere inside bci_train's fold evaluation itself).
fprintf('DIAGNOSTIC nTrials = %d\n', nTrials);
fprintf('DIAGNOSTIC foldPerm = %s\n', mat2str(foldPerm));
for f = 1:kFolds
    fprintf('DIAGNOSTIC fold %d test = %s\n', f, mat2str(cvScheme{f}{2}));
end

[trainloss, lastmodel, laststats] = bci_train('Data', lastdata, ...
    'Approach', approach, ...
    'TargetMarkers', targetMarkers, ...  % <-- EDIT if labels differ
    'EvaluationScheme', cvScheme);

% Display summary & confusion
fprintf('Training-set loss (misclassification rate): %.4f\n', trainloss);
disp(laststats);

% Save per-fold [TP TN FP FN mcr] metrics
nFolds = numel(laststats.per_fold);
foldstats_bcilab = zeros(nFolds, 5);
for f = 1:nFolds
    pf = laststats.per_fold(f);
    foldstats_bcilab(f,:) = [pf.TP, pf.TN, pf.FP, pf.FN, pf.mcr];
end
writematrix(foldstats_bcilab, fullfile(datapath,'result_bcilab.csv'));

% Pooled confusion matrix from actual per-trial predictions (not just
% averaged fold rates). per_fold.pred is a BCILAB discrete-prediction
% cell {'disc', scores, classlist}; the hard label is the argmax score.
allTarg = []; allPred = [];
for f = 1:nFolds
    pf = laststats.per_fold(f);
    targ_f = pf.targ(:);
    scores_f = pf.pred{2};
    classlist_f = pf.pred{3};
    [~, winCol] = max(scores_f, [], 2);
    pred_f = classlist_f(winCol);
    allTarg = [allTarg; targ_f]; %#ok<AGROW>
    allPred = [allPred; pred_f]; %#ok<AGROW>
end
classes = unique(allTarg);  % [1;2] = {hand, foot}
confusionCounts = zeros(numel(classes));
for a = 1:numel(classes)
    for b = 1:numel(classes)
        confusionCounts(a,b) = sum(allTarg == classes(a) & allPred == classes(b));
    end
end
fprintf('Pooled confusion matrix (rows = true class, cols = predicted class, order = %s):\n', mat2str(classes'));
disp(confusionCounts);
writematrix(confusionCounts, fullfile(datapath,'confusion_matrix_bcilab.csv'));

% Visualize CSP spatial patterns directly from the trained model.
% lastmodel.featuremodel.patterns holds the Haufe-style forward patterns
% (rows = filters), .chanlocs the channel locations.
fm = lastmodel.featuremodel;
nPatterns = size(fm.patterns, 1);
% Height reduced from 800px (the 2x3 grid had more vertical margin than
% its content needed); text color forced to black, same dark-mode
% reason as the other figures in this pipeline. Height nudged back up
% slightly from an initial 620px attempt, which left the sgtitle
% slightly overlapping the "Pattern 2" subplot title.
figCSP = figure('Name','CSP Patterns (BCILAB)','Color','w','Position',[100 100 1000 680]);
set(figCSP,'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k');
for k = 1:nPatterns
    subplot(2, ceil(nPatterns/2), k);
    topoplot(fm.patterns(k,:), fm.chanlocs, 'electrodes','off');
    title(sprintf('Pattern %d', k), 'Color','k');
end
sgt = sgtitle('CSP spatial patterns (S023), trained via BCILAB ParadigmCSP');
sgt.FontSize = 11;
sgt.Color = 'k';
% Previously investigated as an unresolved rendering quirk (renderer
% choice, figure height) but actually traced to the same root cause
% seen in the other figures in this pipeline: MATLAB's live
% figure-interaction UI (axes toolbar, resize handles) getting captured
% mid-render by saveas, triggered by the known uint64 graphics
% conflict. clean_save disables that interactivity and forces a full
% render before saving.
clean_save(gcf, fullfile(fullfile(projectroot,'Results&Figures'), 'S023_CSP_patterns.png'));

function clean_save(figHandle, outPath)
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
