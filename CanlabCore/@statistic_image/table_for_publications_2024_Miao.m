function [outputT_pos, outputT_neg] = table_for_publications_2024_Miao(stats_img, varargin)
% This function is designed to generate an fMRI activation table for use in
% main texts of papers.
% 
% Specifically, the tables generated have the following characteristics
% (1) Each row of the table is one cluster, or "blob", of activations
% (2) Columns: atlas labels, heuristic names (now only work for canlab2023), 
% peak coordinates, and t values
% (3) Atlas labels and heuristic names can have multiple values, separate
% by commas
%
% This function works by concatenating the ouputs from
% `autolabel_regions_using_atlas()` and `table()`
% 
% Zizhuang Miao
% 09/04/2023
%
% :Usage:
% ::
%
%    [outputT_pos, outputT_neg] = table_for_publications_2024_Miao(stats_img, varargin)
%
% :Inputs:
%
%    **stats_img**:
%         A statistic_image object
%
% :Optional keyword arguments:
%
%    **'atlas'**:
%        Followed by a char array with the keyword or name of an 
%        atlas-class object with labels.
%        If not provided, default to 'canlab2023'
%
%    **'doneg'**:
%        Return both tables with positive activations and tables with 
%        negative activations. Default to false.
%    
%    **'noverbose'**:
%        Suppress the output tables (only work on the modified `table()`
%        function)
%
%    **'nolegend'**:
%        Suppress table legends
%
%    **'threshold'**:
%        Followed by the threshold for the atlas. Default to 0.
%
% :Outputs:
%
%    **outputT_pos**
%        A Matlab table object with one row being a cluster/blob of
%        positive activation.
% 
%    **outputT_neg**
%        Same table as above, with negative activation.

narginchk(1, Inf)

if (size(stats_img.dat, 2) > 1)
    error('Use this function with fmri_data or image_vector objects containing only a single image. Use get_wh_image() to select one.')
end

% Default
atlas_obj = [];
nTables = 1;    % the number of tables to produce
                % 1 for positive only, 2 for both positive and negative
verbosestr = "";
legendstr = "";
thr = 0;

for i = 1:length(varargin)
    if ischar(varargin{i})
        switch varargin{i}

            case {'atlas'}, atlas_obj = load_atlas(varargin{i+1});
            
            case {'doneg'}, nTables = 2;
            
            case {'noverbose'}, verbosestr = ", 'noverbose'";

            case {'nolegend'}, legendstr = ", 'nolegend'";

            case {'threshold'}, thr = varargin{i+1};
        end
    end
end

% -------------------------------------------------------------------------
% PREP ATLAS AND OBJECT
% -------------------------------------------------------------------------

% Load default atlas if needed
if isempty(atlas_obj)
    atlas_obj = load_atlas('canlab2023');
end

% threshold atlas
atlas_thr = atlas_obj.threshold(thr);

% find network labels for all regions
% iterate over labels and find corresponding network labels from canlab2018
% cr. Michael Sun
canlab2018 = load_atlas('canlab2018');
nets = canlab2018.labels_2;
labels = atlas_thr.labels;
sorted_nets = cell(1,length(labels));
for i = 1:length(labels)
    if contains(labels{i},'Ctx')
        sorted_nets{i} = nets{strcmp(canlab2018.labels,labels{i})};
    else
        sorted_nets{i} = 'Sub-cortex';
    end
end
atlas_thr.labels_5 = sorted_nets;    % labels_5 should be a safe field name
                                     % with no values in the field before
% create a new atlas object with the network labels
atlas_net = atlas_thr.downsample_parcellation('labels_5');    

% parcellate stats_img into (positve and negative) regions
regions = region(stats_img);
r = cell(1, 2);    % a cell object that stores positive and negative regions
r_relabeled = cell(1, 2);
outputTables = cell(1, 2);   % a cell that stores output tables
[r{1}, r{2}] = posneg_separate(regions);

% -------------------------------------------------------------------------
% CRATE AND CONCATENATE TABLES
% -------------------------------------------------------------------------
for t = 1:nTables
    % first, use `autolabel_...` to get each blob and names of atlas regions
    [r_relabeled{t}, atlasT, ~, atlasR] ...
        = autolabel_regions_using_atlas(r{t}, atlas_thr);

    % only retain blobs that covered at least one atlas region
    atlasR = atlasR(atlasT.Atlas_regions_covered>0, :);
    atlasT = atlasT(atlasT.Atlas_regions_covered>0, :);
    
    % next, create a table with network names to be attached to the final table
    [~, networkT] = autolabel_regions_using_atlas(r_relabeled{t}, atlas_net);
    
    % then, find peak coordinates and stats values for each blob
    eval(strcat("[~, ~, xyzT] = table(r_relabeled{t}, 'atlas_obj', atlas_thr", ...
        legendstr, verbosestr, ");"))

    atlasT.heuristic_names = cell(height(atlasT), 1);

    % add peak coordinates and atlas region names
    [atlasT.x, atlasT.y, atlasT.z, atlasT.Region, atlasT.t] ...
        = deal(NaN(height(atlasT), 1));
    for i = 1:height(atlasT)
        atlasT.Region(i) = i;     % name the regions by number
        atlasT.all_regions_covered{i} = atlasR{i};
        % find corresponding clusters across two tables by volumes and #regions
        nVolume = atlasT.Region_Vol_mm(i);
        nRegions = atlasT.Atlas_regions_covered(i);
        perc = atlasT.Perc_covered_by_label(i);
        wh = find(xyzT.Volume == nVolume & ...
            xyzT.Atlas_regions_covered == nRegions & ...
            xyzT.Perc_covered_by_label == perc);
        atlasT.x(i) = xyzT.XYZ(wh, 1);
        atlasT.y(i) = xyzT.XYZ(wh, 2);
        atlasT.z(i) = xyzT.XYZ(wh, 3);
        atlasT.t(i) = xyzT.maxZ(i);
    end
    
    % add network names and heuristic names (now only work for canlab2023)
    atlasT.network = cell(height(atlasT), 1);
    for i = 1:height(atlasT)
        % network
        nVolume = atlasT.Region_Vol_mm(i);
        nRegions = atlasT.Atlas_regions_covered(i);
        wh_networks = find(networkT.Region_Vol_mm == nVolume);
        atlasT.network{i} = networkT.modal_label{wh_networks};
        
        % heuristic names (only work for 'canlab2023' now)
        if strcmp(atlas_obj.atlas_name, 'CANLab2023_MNI152NLin2009cAsym_coarse_2mm')
            heuName = cell(1, size(atlasR{i}, 2));
            for j = 1:size(atlasR{i}, 2)
                heuName{j} = atlas_thr.labels_3{strcmp(atlas_thr.labels, atlasR{i}{j})};
            end
            heuName = unique(heuName, 'stable');
            atlasT.heuristic_names{i} = heuName;
        end
    end
    
    % remove useless columns
    atlasT = removevars(atlasT, ...
        {'Voxels', 'Atlas_regions_covered', 'modal_label', ...
        'modal_label_descriptions', 'Perc_covered_by_label', ...
        'Ref_region_perc', 'modal_atlas_index'});
   
    % remove all underlines in region names, and put them as a long string
    atlasT.all_regions_covered = cellfun(@(x) strjoin(x, ', '), ...
        format_strings_for_legend(atlasT.all_regions_covered), ...
        'UniformOutput', false);
    atlasT.heuristic_names = cellfun(@(x) strjoin(x, ', '), ...
        format_strings_for_legend(atlasT.heuristic_names), ...
        'UniformOutput', false);

    % rename columns
    atlasT.Properties.VariableNames = ...
        {'Cluster', 'Volume (mm^3)', 'Atlas region names', ...
        'Heuristic names', 'X', 'Y', 'Z', 'Max t', 'Network'};
    if stats_img.type ~= 'T'
        atlasT = renamevars(atlasT, {'Max t'}, {['Max ', lower(stats_img.type)]});
    end
    outputTables{t} = atlasT;
end

outputT_pos = outputTables{1};
outputT_neg = outputTables{2};
end