% Filtering:  
% This script is intended to use the data generated by readMATandsort.m by
% the data of the TD26CC structure, which is under test now in the dogleg.
% 
% In details it works in two steps:
% - read the matfiles with the data of the experiment 'Exp_<experiment Name>.mat'
% 1)  Process one by one the events, building data lists
%       - 2 lists for the metric values
%       - a list with spike flag
%       - a list with beam charge
%       - a list of the number of pulses past after the previous BD
%       - a list of the time past after the previous BD
% 2)  Set the thresholds and convert lists above into lists of flags
%       - inc_tra_flag and inc_ref_flag are 1 if the event is respecting the metric
%       - bpm1_flag and bpm2_flag are 1 if the charge from BPM is
%         trepassing the treshold. 
%       - hasBeam is the logical AND of bpm1_flag and bpm2_flag
%       - isSpike inherits from the precedent analysis
% 
% --------AND STUFF-------
% 
% REV. 1. by Eugenio Senes and Theodoros Argyropoulos
%
% Last modified 22.04.2016 by Eugenio Senes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
close all; clearvars; clc;
if strcmp(computer,'MACI64')
    addpath(genpath('/Users/esenes/scripts/Dogleg-analysis-master'))
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%% User input %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
datapath_read = '/Users/esenes/swap_out/exp';
datapath_write = '/Users/esenes/swap_out/exp';
expname = 'Exp_Loaded43MW_3';
savename = expname;
%%%%%%%%%%%%%%%%%% Select the desired output %%%%%%%%%%%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%%%%%%%%%%%%% End of user input %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%% Parameters %%%%%%%%%%%%%%%%%%%%%%%
% METRIC
inc_ref_thr = 0.48;
inc_tra_thr = -0.02;
% BPM CHARGE THRESHOLDS
bpm1_thr = -100;
bpm2_thr = -90;
% DELTA TIME FOR SECONDARY DUE TO BEAM LOST
deltaTime_spike = 90;
deltaTime_beam_lost = 90;
% PULSE DELAY
init_delay = 60e-9;
max_delay = 80e-9;
step_len = 4e-9;
comp_start = 5e-7; %ROI start and end
comp_end = 5.5e-7;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Create log file
%create log file and add initial parameters
logID = fopen([datapath_write filesep savename '.log'], 'w+' ); 
msg1 = ['Analysis log for the file ' expname '.mat' '\n' ...
'Created: ' datestr(datetime('now')) '\n \n' ...
'User defined tresholds: \n' ...
'METRIC: \n' ...
'- inc_ref_thr: %3.2f \n' ... 
'- inc_tra_thr: %3.2f \n' ... 
'BPM charge' '\n' ...
'- bpm1_thr: %3.2f' '\n' ...
'- bpm2_thr: %3.2f' '\n' ...
'Time window for clusters ' '\n' ...
'- deltaTime_spike: %3.2f' '\n' ...
'- deltaTime_bem_lost: %3.2f' '\n' ...
'\n'];
fprintf(logID,msg1,inc_ref_thr, inc_tra_thr, bpm1_thr, bpm2_thr,deltaTime_spike,deltaTime_beam_lost);
fclose(logID);
%% Load the files
tic
disp('Loading the data file ....')
load([datapath_read filesep expname '.mat']);
disp('Done.')
toc
disp(' ')

%% Get field names and list of B0 events in the file
event_name = {};
j = 1;
foo = fieldnames(data_struct);
for i = 1:length(foo)
    if strcmp(foo{i}(end-1:end),'B0')
        event_name{j} = foo{i};
        j = j+1;
    end    
end    
clear j, foo;

%% Parse the interesting event one by one and build the arrays of data for selection
% allocation
    %metric
    inc_tra = zeros(1,length(event_name));
    inc_ref = zeros(1,length(event_name));
    %bool for the spike flag
    isSpike = false(1,length(event_name));
    %beam charge
    bpm1_ch = zeros(1,length(event_name));
    bpm2_ch = zeros(1,length(event_name));
    %timestamps list    
    ts_array = zeros(1,length(event_name));
    %pulse past from previous BD list
    prev_pulse = zeros(1,length(event_name));
    %beam lost events
    beam_lost = false(1,length(event_name));
    %peak power
    pk_pwr = zeros(1,length(event_name));
% filling    
for i = 1:length(event_name) 
    inc_tra(i) = data_struct.(event_name{i}).inc_tra;
    inc_ref(i) = data_struct.(event_name{i}).inc_ref;
    isSpike(i) = data_struct.(event_name{i}).spike.flag;
    bpm1_ch(i) = data_struct.(event_name{i}).BPM1.sum_cal;
    bpm2_ch(i) = data_struct.(event_name{i}).BPM2.sum_cal;
    pk_pwr(i) = data_struct.(event_name{i}).INC.max;
    % build a timestamps array
    [~, ts_array(i)] = getFileTimeStamp(data_struct.(event_name{i}).name);
    %build the number of pulse pulse between BD array
    prev_pulse(i) = data_struct.(event_name{i}).Props.Prev_BD_Pulse_Delay;
    %look for beam lost events and flag it
    beam_lost(i) = beamWasLost(data_struct.(event_name{i}).name, bpm1_ch(i), bpm2_ch(i), bpm1_thr, bpm2_thr);
end

%% Metric plotting to check the tresholds
f0 = figure;
figure(f0)
p1 = plot(inc_tra, inc_ref,'b .','MarkerSize',12);
xlabel('(INC-TRA)/(INC+TRA)')
ylabel('(INC-REF)/(INC+REF)')
axis([-0.2 0.5 0.2 0.8])
line(xlim, [inc_ref_thr inc_ref_thr], 'Color', 'r','LineWidth',1) %horizontal line
line([inc_tra_thr inc_tra_thr], ylim, 'Color', 'r','LineWidth',1) %vertical line
title('Interlock criteria review')
legend('Interlocks')



%% Start the filtering 
% filling bool arrays
    %metric criteria
    [inMetric,~,~] = metricCheck(inc_tra, inc_tra_thr, inc_ref, inc_ref_thr);
    %beam charge
    [hasBeam,~,~] = beamCheck(bpm1_ch, bpm1_thr, bpm2_ch, bpm2_thr,'bpm1');
    %find indexes and elements for metric and non-metric events
    metr_idx = find(inMetric);
    nonmetr_idx = find(~inMetric);
    %secondary filter by time after SPIKE
    [~, sec_spike_in] = filterSecondary(ts_array(metr_idx),deltaTime_spike,isSpike(metr_idx));
    [~, sec_spike_out] = filterSecondary(ts_array(nonmetr_idx),deltaTime_spike,isSpike(nonmetr_idx));
    sec_spike = recomp_array(sec_spike_in,metr_idx,sec_spike_out,nonmetr_idx);
    %secondary filter by time after BEAM LOST
    [~, sec_beam_lost_in] = filterSecondary(ts_array(metr_idx),deltaTime_beam_lost,beam_lost(metr_idx));
    sec_beam_lost = recomp_array(sec_beam_lost_in,metr_idx,zeros(1,length(nonmetr_idx)),nonmetr_idx);
% filling event arrays    
    %in the metric
    intoMetr = event_name(inMetric);
    outOfMetr = event_name(~inMetric);
    %candidates = inMetric, withBeam, not beam lost and not after spike
    BD_candidates = event_name(inMetric & ~isSpike & ~(sec_spike) & ~beam_lost & ~(sec_beam_lost));
    BD_candidates_beam = event_name(inMetric & hasBeam & ~isSpike & ~(sec_spike) & ~(sec_beam_lost));
    BD_candidates_nobeam = event_name(inMetric & ~hasBeam & ~isSpike & ~(sec_spike) & ~(sec_beam_lost));
    %interlocks = "candidates" out of metric
    interlocks_out = event_name(~inMetric & ~isSpike & ~(sec_spike) & ~beam_lost & ~(sec_beam_lost));
    %spikes
    spikes_inMetric =  event_name(inMetric & isSpike);
    spikes_outMetric =  event_name(~inMetric & isSpike);
    %missed beams
    missed_beam_in = event_name(inMetric &beam_lost);
    missed_beam_out = event_name(~inMetric &beam_lost);
    %clusters
    missed_beam_cluster = event_name(inMetric &sec_beam_lost);
    spike_cluster = event_name(inMetric & sec_spike & ~isSpike);
    spike_cluster_out = event_name(~inMetric & sec_spike & ~isSpike);
   

%% Report message and crosscheck of lengths
disp(['Analysis done! '])
%open the log file and append
logID = fopen([datapath_write filesep savename '.log'], 'a' ); 
%gather data and build the message
%%INTO THE METRIC
l1 = length(BD_candidates);
l2 = length(spikes_inMetric);
l3 = length(spike_cluster);
l4 = length(missed_beam_in);
l5 = length(missed_beam_cluster);
msg2 = ['BD candidates found: ' num2str(length(inMetric)) ' of which ' num2str(length(intoMetr)) ' are into the metric' '\n' ...
'Into the metric:' '\n' ...
' - ' num2str(l1) ' are good candidates' '\n' ...
' - ' num2str(l2) ' are spikes' '\n' ...
' - ' num2str(l3) ' are secondary triggered by spikes' '\n' ...
' - ' num2str(l4) ' are missed beam pulses' '\n' ...
' - ' num2str(l5) ' are secondary triggered by beam lost' '\n' ...
'-------' '\n' ...
'  ' num2str(l1+l2+l3+l4+l5) ' events in metric' '\n \n' ...
'Of the ' num2str(l1) ' good candidates:' '\n' ...
' - ' num2str(length(BD_candidates_beam)) ' have the beam' '\n' ...
' - ' num2str(length(BD_candidates_nobeam)) ' do not have the beam' '\n \n' ...
];
%%OUT OF THE METRIC
l1 = length(interlocks_out);
l2 = length(spikes_outMetric);
l3 = length(spike_cluster_out);
msg3 = ['Out of the metric:' '\n' ...
' - ' num2str(l1) ' are BDs ' '\n' ...
' - ' num2str(l2) ' are spikes' '\n' ...
' - ' num2str(l3) ' are secondary triggered by spikes' '\n' ...
'-------' '\n' ...
'  ' num2str(l1+l2+l3) ' events out of the metric' '\n \n' ...
];
% print to screen (1) and to log file
fprintf(1,msg2);
fprintf(1,msg3);
fprintf(logID,msg2);
fprintf(logID,msg3);
fclose(logID);

%% Signal alignment check
data_struct = signalDelay( BD_candidates, data_struct, init_delay, max_delay, step_len, comp_start, comp_end);

%% Distributions plots
% figure(f3)
% histogram(pk_pwr,1e6)
% average power

% cluster length



%% Interactive plot (read version)
%user ineraction


% split candidates in w/ and w/o beam
% time delay
% time interval in one file processing in readMATandsort.m

% distribution of spikes and clusters and stuff in the last unloaded run




gone = false;
interactivePlot = false;
while ~gone
    str_input = input('Go to viewer ? (Y/N)','s');
    switch lower(str_input)
        case 'y'
            interactivePlot = true;
            gone = true;
        case 'n'
            interactivePlot = false;
            gone = true;
        otherwise
            disp('Enter a valid character')
            gone = false;
    end
end


if interactivePlot
    %Build the dataset to plot (IN METRIC):
    %candidates
    BDC_in_x = zeros(1,length(BD_candidates));
    BDC_in_y = zeros(1,length(BD_candidates));
    for k = 1:length(BD_candidates)
        BDC_in_x(k) = data_struct.(BD_candidates{k}).inc_tra;
        BDC_in_y(k) = data_struct.(BD_candidates{k}).inc_ref;
    end
    %spikes
    sp_in_x = zeros(1,length(spikes_inMetric));
    sp_in_y = zeros(1,length(spikes_inMetric));
    for k = 1:length(spikes_inMetric)
        sp_in_x(k) = data_struct.(spikes_inMetric{k}).inc_tra;
        sp_in_y(k) = data_struct.(spikes_inMetric{k}).inc_ref;
    end
    %spike cluster
    sp_c_in_x = zeros(1,length(spike_cluster));
    sp_c_in_y = zeros(1,length(spike_cluster));
    for k = 1:length(spike_cluster)
        sp_c_in_x(k) = data_struct.(spike_cluster{k}).inc_tra;
        sp_c_in_y(k) = data_struct.(spike_cluster{k}).inc_ref;
    end   
    %missed beam
    miss_in_x = zeros(1,length(missed_beam_in));
    miss_in_y = zeros(1,length(missed_beam_in));
    for k = 1:length(missed_beam_in)
        miss_in_x(k) = data_struct.(missed_beam_in{k}).inc_tra;
        miss_in_y(k) = data_struct.(missed_beam_in{k}).inc_ref;
    end
    %missed beam cluster
    miss_c_in_x = zeros(1,length(missed_beam_cluster));
    miss_c_in_y = zeros(1,length(missed_beam_cluster));
    for k = 1:length(missed_beam_cluster)
        miss_c_in_x(k) = data_struct.(missed_beam_cluster{k}).inc_tra;
        miss_c_in_y(k) = data_struct.(missed_beam_cluster{k}).inc_ref;
    end
    %OUT OF METRIC:
    %interlocks
    BDC_out_x = zeros(1,length(interlocks_out));
    BDC_out_y = zeros(1,length(interlocks_out));
    for k = 1:length(interlocks_out)
        BDC_out_x(k) = data_struct.(interlocks_out{k}).inc_tra;
        BDC_out_y(k) = data_struct.(interlocks_out{k}).inc_ref;
    end
    %spikes
    sp_out_x = zeros(1,length(spikes_outMetric));
    sp_out_y = zeros(1,length(spikes_outMetric));
    for k = 1:length(spikes_outMetric)
        sp_out_x(k) = data_struct.(spikes_outMetric{k}).inc_tra;
        sp_out_y(k) = data_struct.(spikes_outMetric{k}).inc_ref;
    end
    %spike cluster
    sp_c_out_x = zeros(1,length(spike_cluster_out));
    sp_c_out_y = zeros(1,length(spike_cluster_out));
    for k = 1:length(spike_cluster_out)
        sp_c_out_x(k) = data_struct.(spike_cluster_out{k}).inc_tra;
        sp_c_out_y(k) = data_struct.(spike_cluster_out{k}).inc_ref;
    end   
    % merge same type, in metric before
    BDC_x = [BDC_in_x BDC_out_x];
    BDC_y = [BDC_in_y BDC_out_y];
    sp_x = [sp_in_x sp_out_x];
    sp_y = [sp_in_y sp_out_y]; 
    sp_c_x = [sp_c_in_x sp_c_out_x];
    sp_c_y = [sp_c_in_y sp_c_out_y];

    %finally plot
    prompt = 'Select an event with the cursor and press ENTER (any other to exit)';
    f1 = figure('Position',[50 50 1450 700]);
    figure(f1);
    datacursormode on;
    subplot(5,5,[1 2 3 6 7 8 11 12 13])
    plot(BDC_x, BDC_y,'r .',sp_x,sp_y,'g .', sp_c_x,sp_c_y,'b .',...
        miss_in_x,miss_in_y,'c.',miss_c_in_x,miss_c_in_y,'m .','MarkerSize',15);
    legend('BDs','Spikes','After spike','Missed beam','After missed beam')
    xlabel('(INC-TRA)/(INC+TRA)')
    ylabel('(INC-REF)/(INC+REF)')
    axis([-0.2 0.5 0.2 0.8]);
    line(xlim, [inc_ref_thr inc_ref_thr], 'Color', 'r','LineWidth',1) %horizontal line
    line([inc_tra_thr inc_tra_thr], ylim, 'Color', 'r','LineWidth',1) %vertical line
    title('Interlock distribution');

    %x axis thicks for signals plotting
    timescale = 1:800;
    timescale = timescale*data_struct.(event_name{1}).INC.Props.wf_increment;

    %init the small graphs
    subplot(5,5,[4 5 9 10 14 15]) %RF signals plot
    title('RF signals');
    sp6 = subplot(5,5,[19 20 24 25]); %pulse tuning plot
    title('Pulse tuning')
    sp7 = subplot(5,5,[16 17 18 21 22 23]); %BPMs plot
    ylim(sp7, [-1.8 0.05]);
    title('BPM signals');
    % user interaction
    exitCond = false;
    while isempty ( input(prompt,'s') )%keep on spinning while pressing enter
        %get cursor position
        dcm_obj = datacursormode(f1);
        info_struct = getCursorInfo(dcm_obj);

        switch info_struct.Target.DisplayName
            % !!!! Must match the legend
            case 'BDs'
                if info_struct.DataIndex <= length(BDC_in_x)
                    fname = BD_candidates{info_struct.DataIndex};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                else
                    fname = interlocks_out{info_struct.DataIndex-length(BDC_in_x)};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                end
            case 'Spikes'
                if info_struct.DataIndex <= length(sp_in_x)
                    fname = spikes_inMetric{info_struct.DataIndex};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                else
                    fname = spikes_outMetric{info_struct.DataIndex-length(sp_in_x)};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                end
            case 'After spike'
                if info_struct.DataIndex <= length(sp_c_in_x)
                    fname = spike_cluster{info_struct.DataIndex};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                else
                    fname = spike_cluster_out{info_struct.DataIndex-length(sp_c_in_x)};
                    print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
                end    
            case 'Missed beam'
                fname = missed_beam_in{info_struct.DataIndex};
                print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
            case 'After missed beam'
                fname = missed_beam_cluster{info_struct.DataIndex};
                print_subPlots(fname, timescale, data_struct,bpm1_thr,bpm2_thr)
            otherwise
                warning('Type not recognized')
        end

    end
end %end user choice