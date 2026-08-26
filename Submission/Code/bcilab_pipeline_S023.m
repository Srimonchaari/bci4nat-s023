% -------------------------------------------------------------
% BCILAB CSP+LDA runner (mirrors your GUI workflow)
% Requirements: BCILAB on path; EEGLAB; preprocessed set available
% Input: S023_cleaned_continuous.set (continuous, ICA-cleaned, NOT yet
%        epoched) from the EEGLAB preprocessing script. BCILAB's own
%        SignalProcessing/EpochExtraction step does the epoching here -
%        do NOT feed it the already-epoched S023_MI_preproc.set, since
%        BCILAB's Resampling/FIRFilter/EpochExtraction options are
%        designed to run on continuous data and will misbehave (double
%        filtering, double epoching) on data that is already epoched.
% -------------------------------------------------------------
projectroot = '/Users/srimonchaari/Documents/Projects/BCI';   % <-- EDIT if repo moves
addpath(fullfile(projectroot, 'Toolboxes', 'eeglab2026.0.0'));
addpath(fullfile(projectroot, 'Toolboxes', 'BCILAB-devel'));
% NOTE: startup output is captured and discarded here. It is entirely
% cosmetic noise from BCILAB's vendored legacy EEGLAB copy
% (dependencies/eeglab13_4_4b) trying to add menu items for ~10 unused
% hardware-format import plugins (BDF, MFF, NeurOne, etc.) that are
% incompatible with this MATLAB version's uimenu() parent-object
% requirement - confirmed by reading eegplugin_bdfimport.m directly: it
% calls findobj(fig,'tag','import data') to locate a menu handle, which
% returns empty in this EEGLAB version, and uimenu([], ...) then fails.
% None of these plugins are used by this pipeline (only .set/.fdt files
% are loaded). If startup itself fails, remove evalc() here temporarily
% to see the real error text.
evalc('eeglab; bcilab;');

% NOTE: BCILAB's dependencies/fileio-2014-06-22/@uint64/ folder overrides
% MATLAB's built-in uint64 arithmetic operators (plus, minus, times, abs,
% max, min, rdivide) with its own compiled versions. This conflicts with
% MATLAB's own graphics/figure-interaction code, which uses uint64
% internally for figure handles, causing a wall of harmless-looking but
% disruptive "Invalid type of input arguments (should be uint64)" errors
% on every subsequent figure/plot/save call in the session. Removing this
% folder from the path after BCILAB has finished loading eliminates the
% conflict; BCILAB itself does not need this folder again once startup is
% complete (it only provides legacy hardware file-I/O helpers unused by
% this pipeline).
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

% Approach: CSP (3 pairs) + LDA. Only EpochExtraction is applied here
% (reference/filter/resample/ICA were already done in the EEGLAB
% preprocessing script and are baked into S023_cleaned_continuous.set).
% NOTE on argument nesting: confirmed against bci_train.m's own worked
% examples (see its help text, e.g. the SpecCSP example around line 256)
% rather than inferred from class code alone - the correct top-level
% structure is {paradigm, 'SignalProcessing',{...}, 'Prediction',
% {'FeatureExtraction',{...}, 'MachineLearning',{...}}}. 'PatternPairs'
% goes inside FeatureExtraction (it's an argument of ParadigmCSP's
% feature_adapt()); 'MachineLearning' wraps ml_train, whose classifier
% choice is itself an arg_subswitch named 'Learner' (default 'lda').
% NOTE: 'FIRFilter','off' AND 'Resampling','off' are both required here -
% confirmed by inspecting the trained model's actual filter_graph.
% ParadigmCSP's preprocessing_defaults() applies its own default FIR
% filter ([6 8 28 32] Hz, minimum-phase) AND its own default resample-to-
% 100Hz step, UNLESS both are explicitly disabled, even though our
% SignalProcessing spec only mentioned EpochExtraction. This silently
% re-processed data that our EEGLAB script had already band-pass filtered
% (zero-phase, [7 30] Hz) and resampled - disabling FIRFilter alone raised
% accuracy from 68.89% to 73.33%, confirming this was a real effect; the
% remaining Resampling stage may account for further difference from the
% manual-MATLAB pipeline's 88.89% on the same cleaned data.
approach = {'CSP', ...
    'SignalProcessing', {'FIRFilter','off', 'Resampling','off', 'EpochExtraction',[0.5 3.5]}, ...
    'Prediction', {'FeatureExtraction', {'PatternPairs', 3}, ...
                    'MachineLearning', {'Learner', 'lda'}}};

% Calibrate with 5-fold CV; set your markers.
% NOTE: this BCILAB version's bci_train has no 'Folds' or 'ForceRestart'
% argument (confirmed by inspecting bci_train.m's arg_define list) -
% k-fold count is passed as a plain number directly to 'EvaluationScheme'
% (see utl_crossval.m: k-fold randomized CV is scheme = k).
% NOTE on output arguments: bci_train's real signature (confirmed from its
% own function declaration and help text) is
% [measure, model, stats] = bci_train(...) - three outputs, in that order.
% Capturing only two outputs as [lastmodel, laststats] silently receives
% the loss/measure scalar into lastmodel and the model struct into
% laststats, dropping the actual per-fold statistics entirely - this was
% the root cause of "laststats" printing as a model struct with no
% accuracy/confusion-matrix fields.
[trainloss, lastmodel, laststats] = bci_train('Data', lastdata, ...
    'Approach', approach, ...
    'TargetMarkers', {'T1','T2'}, ...  % <-- EDIT if labels differ
    'EvaluationScheme', 5);

% Display summary & confusion
fprintf('Training-set loss (misclassification rate): %.4f\n', trainloss);
disp(laststats);

% Save per-fold metrics similar to result.csv.
% NOTE: laststats.per_fold is a 1xN struct array (fields TP/TN/FP/FN/mcr
% among others, confirmed by inspecting laststats.per_fold(1)), not a
% plain numeric matrix - writematrix/csvwrite cannot serialize a struct
% array directly. Extract the same [TPR TNR FPR FNR Error] columns used
% by csp_lda_cv_S023.m's result.csv for a directly comparable format.
nFolds = numel(laststats.per_fold);
foldstats_bcilab = zeros(nFolds, 5);
for f = 1:nFolds
    pf = laststats.per_fold(f);
    foldstats_bcilab(f,:) = [pf.TP, pf.TN, pf.FP, pf.FN, pf.mcr];
end
writematrix(foldstats_bcilab, fullfile(datapath,'result_bcilab.csv'));

% Pooled confusion matrix (exact trial counts, not just per-fold rates).
% Confirmed by inspection: per_fold(f).targ is a plain Nx1 numeric label
% vector (1=hand/T1, 2=foot/T2), but per_fold(f).pred is a BCILAB
% "discrete prediction" cell {'disc', [Nx2 double] scores, [2x1 double]
% classlist} - NOT a hard label vector. The Nx2 matrix holds per-trial
% class probabilities/scores (columns ordered per the classlist in cell
% 3), so the hard predicted label per trial is recovered by taking the
% argmax across columns and mapping back through the classlist.
allTarg = []; allPred = [];
for f = 1:nFolds
    pf = laststats.per_fold(f);
    targ_f = pf.targ(:);
    scores_f = pf.pred{2};      % Nx2 per-trial class scores
    classlist_f = pf.pred{3};   % 2x1 class labels, column order matches scores_f
    [~, winCol] = max(scores_f, [], 2);
    pred_f = classlist_f(winCol);
    allTarg = [allTarg; targ_f]; %#ok<AGROW>
    allPred = [allPred; pred_f]; %#ok<AGROW>
end
classes = unique(allTarg);  % expect [1;2] for {'T1','T2'} = {hand, foot}
confusionCounts = zeros(numel(classes));
for a = 1:numel(classes)
    for b = 1:numel(classes)
        confusionCounts(a,b) = sum(allTarg == classes(a) & allPred == classes(b));
    end
end
fprintf('Pooled confusion matrix (rows = true class, cols = predicted class, order = %s):\n', mat2str(classes'));
disp(confusionCounts);
writematrix(confusionCounts, fullfile(datapath,'confusion_matrix_bcilab.csv'));

% Visualize CSP spatial patterns directly from the trained BCILAB model.
% Confirmed by inspection: lastmodel.featuremodel is the struct written
% by ParadigmCSP.m's feature_adapt(), which stores Haufe-style forward
% projected patterns in .patterns (rows = the 6 filters, in the same
% [top 3, bottom 3] order as PatternPairs=3 selects them) and channel
% locations in .chanlocs. This replaces the earlier manual-MATLAB CSP
% implementation (csp_lda_cv_S023.m) as the source of Figure 3 in the
% report, so the submitted figure is generated entirely through BCILAB
% rather than a hand-written eig()-based CSP.
fm = lastmodel.featuremodel;
nPatterns = size(fm.patterns, 1);
figure('Name','CSP Patterns (BCILAB)','Color','w');
for k = 1:nPatterns
    subplot(2, ceil(nPatterns/2), k);
    topoplot(fm.patterns(k,:), fm.chanlocs, 'electrodes','off');
    title(sprintf('Pattern %d', k));
end
sgtitle('CSP spatial patterns (S023), trained via BCILAB ParadigmCSP');
saveas(gcf, fullfile(fullfile(projectroot,'Results&Figures'), 'S023_CSP_patterns.png'));
fprintf('Saved: %s\n', fullfile(projectroot,'Results&Figures','S023_CSP_patterns.png'));
