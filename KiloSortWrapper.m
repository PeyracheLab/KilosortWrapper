function savepath = KiloSortWrapper(varargin)
% Creates channel map from Neuroscope xml files, runs KiloSort and
% writes output data to Neurosuite format or Phy.
% 
% USAGE
%
% KiloSortWrapper()
% Should be run from the data folder, and file basenames are the
% same as the name as current directory
%
% KiloSortWrapper(varargin)
%
% INPUTS
% basepath           path to the folder containing the data
% basename           file basenames (of the dat and xml files)
% config             Specify a configuration file to use from the
%                    ConfigurationFiles folder. e.g. 'Omid'
% GPU_id             Specify the GPU id
%
% Dependencies:  KiloSort (https://github.com/cortex-lab/KiloSort)
% 
% Copyright (C) 2016 Brendon Watson and the Buzsakilab
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
disp('Running Kilosort spike sorting with the Buzsaki lab wrapper')

%% If function is called without argument
p = inputParser;
basepath = cd;
[~,basename] = fileparts(basepath);

addParameter(p,'basepath',basepath,@ischar)
addParameter(p,'basename',basename,@ischar)
addParameter(p,'GPU_id',1,@isnumeric)

parse(p,varargin{:})

basepath = p.Results.basepath;
basename = p.Results.basename;
GPU_id = p.Results.GPU_id;

cd(basepath)

rootZ = basepath; % the raw data binary file is in this folder
rootH = '/mnt/DataSSD'; % path to temporary binary file (same size as data, should be on fast SSD)

ops.fproc   = fullfile(rootH, 'temp_wh.dat'); % proc file on a fast SSD

%% Checking if dat and xml files exist
if ~exist(fullfile(basepath,[basename,'.xml']))
    warning('KilosortWrapper  %s.xml file not in path %s',basename,basepath);
    return
elseif ~exist(fullfile(basepath,[basename,'.dat']))
    warning('KilosortWrapper  %s.dat file not in path %s',basename,basepath)
    return
end


%% Creates a channel map file
disp('Creating ChannelMapFile')
createChannelMapFile_KSW(basepath,basename,'staggered');



%% Loading configurations
XMLFilePath = fullfile(basepath, [basename '.xml']);
% if exist(fullfile(basepath,'StandardConfig.m'),'file') %this should actually be unnecessary
%     addpath(basepath);
% end
ec = exist('config');
if ec ~= 1
    disp('Running Kilosort with standard settings')
    ops = KilosortConfiguration(XMLFilePath);
else
    disp('Running Kilosort with user specific settings')
    config_string = str2func(['KiloSortConfiguration_' config_version]);
    ops = config_string(XMLFilePath);
    clear config_string;
end

%% % Defining SSD location if any

ops.fproc = fullfile(basepath,'temp_wh.dat');
%SSD_path = 'K:\Kilosort';

% if isunix
%     %fname = KiloSortLinuxDir(basename,basepath,gpuDeviceNum);
%     fname = KiloSortLinuxDir(basename,basepath,GPU_id);
%     
%     ops.fproc = fname;
% else
%     if isdir(SSD_path)
%         FileObj = java.io.File(SSD_path);
%         free_bytes = FileObj.getFreeSpace;
%         dat_file = dir(fullfile(basepath,[basename,'.dat']));
%         if dat_file.bytes*1.1<FileObj.getFreeSpace
%             disp('Creating a temporary dat file on the SSD drive')
%             ops.fproc = fullfile(SSD_path, [basename,'_temp_wh.dat']);
%         else
%             warning('Not sufficient space on SSD drive. Creating local dat file instead')
%             ops.fproc = fullfile(basepath,'temp_wh.dat');
%         end
%     else
%         ops.fproc = fullfile(basepath,'temp_wh.dat');
%     end
% end
%%

KSpath = '/home/adrien/Dropbox (Peyrache Lab)/Peyrache Lab Team Folder/Code/Toolbox/KiloSort';

if ~exist(KSpath,'dir')
    error('The Kilosort path does not exist')
end

if ops.GPU
    disp('Initializing GPU')
    gpudev = gpuDevice(GPU_id); % initialize GPU (will erase any existing GPU arrays)
end
if strcmp(ops.datatype , 'openEphys')
   ops = convertOpenEphysToRawBInary(ops);  % convert data, only for OpenEphys
end

%% Lauches KiloSort
disp('Running Kilosort pipeline')
disp('PreprocessingData')
[rez, DATA, uproj] = preprocessData(ops); % preprocess data and extract spikes for initialization

disp('Fitting templates')
rez = fitTemplates(rez, DATA, uproj);  % fit templates iteratively

disp('Extracting final spike times')
rez = fullMPMU(rez, DATA); % extract final spike times (overlapping extraction)

clear DATA

%% posthoc merge templates (under construction)
% save matlab results file
CreateSubdirectory = 0;
if CreateSubdirectory
    timestamp = ['Kilosort_' datestr(clock,'yyyy-mm-dd_HHMMSS')];
    savepath = fullfile(basepath, timestamp);
    mkdir(savepath);
    copyfile([basename '.xml'],savepath);
else
    savepath = fullfile(basepath);
end
rez.ops.basepath = basepath;
rez.ops.basename = basename;
rez.ops.savepath = savepath;
disp('Saving rez file')
save(fullfile(savepath,  'rez.mat'), 'rez', '-v7.3');

%% export python results file for Phy
if ops.export.phy
    disp('Converting to Phy format')
    rezToPhy_KSW(rez);
end

%% export Neurosuite files
if ops.export.neurosuite
    disp('Converting to Klusters format')
    load('rez.mat')
    rez.ops.root = pwd;
    clustering_path = pwd;
    basename = rez.ops.basename;
    rez.ops.fbinary = fullfile(pwd, [basename,'.dat']);
    Kilosort2Neurosuite(rez)
    
    %writeNPY(rez.ops.kcoords, fullfile(clustering_path, 'channel_shanks.npy'));

    %phy_export_units(clustering_path,basename);
end

%% Remove temporary file and resetting GPU
delete(ops.fproc);
%reset(gpudev)
gpuDevice([])
disp('Kilosort Processing complete')
