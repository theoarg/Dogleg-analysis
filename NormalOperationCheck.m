% NormalOperationCheck:  
% This script is intended to use the Norm files generated by readMATandsort.m by
% the data of the TD26CC structure, which is under test now in the dogleg.
%
% The aim of the script is to check the proper working of the machine
% using the backup pulses rather than the BD pulses.
% 
% REV. 1. by Eugenio Senes and Theodoros Argyropoulos
%
% Last modified 02.06.2016 by Eugenio Senes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
close all; clearvars ; clc;
if strcmpi(computer,'MACI64') %just hit add to path when prompted
    addpath(genpath('/Users/esenes/scripts/Dogleg-analysis-master'))
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%% User input %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
datapath_read = '/Users/esenes/swap_out/exp';
datapath_write = '/Users/esenes/swap_out/exp';
datapath_write_plot = '/Users/esenes/swap_out/exp/plots';
datapath_write_fig = '/Users/esenes/swap_out/exp/figs';
fileName = 'Norm_full_Loaded43MW_3';
savename = fileName;
%%%%%%%%%%%%%%%%%%%%%%%%%% End of user input %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%% Parameters %%%%%%%%%%%%%%%%%%%%%%%
% BPM CHARGE THRESHOLDS
bpm1_thr = -100;
bpm2_thr = -90;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% pulse begin/end for probability
pbeg = 400;
pend = 474;

%% Create log file
%create log file and add initial parameters
logID = fopen([datapath_write filesep savename '.log'], 'w+' ); 
msg1 = ['Analysis log for the normal pulses of the file ' fileName '.mat' '\n' ...
'Created: ' datestr(datetime('now')) '\n \n' ...
'User defined tresholds: \n' ...
'BPM charge' '\n' ...
'- bpm1_thr: %3.2f' '\n' ...
'- bpm2_thr: %3.2f' '\n' ...
'\n'];
fprintf(logID,msg1, bpm1_thr, bpm2_thr);
fclose(logID);

%% Load the BD files
tic
disp('Loading the data file ....')
load([datapath_read filesep fileName '.mat']);
disp('Done.')
toc
disp(' ')

%% Get field names and list of L0 events in the file
event_name = {};
j = 1;
foo = fieldnames(data_struct);
for i = 1:length(foo)
    if strcmp(foo{i}(end-1:end),'L0')
        event_name{j} = foo{i};
        j = j+1;
    end    
end    
clear j, foo;
%% Parse the interesting event one by one and build the arrays of data for selection
% allocation
    %beam charge
    bpm1_ch = zeros(1,length(event_name));
    bpm2_ch = zeros(1,length(event_name));
    %timestamps list    
    ts_array = zeros(1,length(event_name));
% filling    
for i = 1:length(event_name) 
    bpm1_ch(i) = data_struct.(event_name{i}).BPM1.sum_cal;
    bpm2_ch(i) = data_struct.(event_name{i}).BPM2.sum_cal;
    % build a timestamps array
    [~, ts_array(i)] = getFileTimeStamp(data_struct.(event_name{i}).name);
    
    %probability of BD is int(P^3 dt)
    p3 = data_struct.(event_name{i}).INC.data_cal (pbeg:pend);
    p3 = p3.^3;
    dt = 4e-9;
    prob(i) = sum(p3*dt);
end

%% filling for plotting
    %peak and average power
    pk_pwr = zeros(1,length(event_name));
    avg_pwr = zeros(1,length(event_name));
    %tra peak power
    pk_tra = zeros(1,length(event_name));
    %tuning
    tuning_slope = zeros(1,length(event_name));
    tuning_delta = zeros(1,length(event_name));
    failSlope = 0;
    failDelta = 0;
    %pulse length
    top_len = zeros(1,length(event_name));
    mid_len = zeros(1,length(event_name));
    bot_len = zeros(1,length(event_name));
    fail_m1=0;
for i = 1:length(event_name) 
    pk_pwr(i) = data_struct.(event_name{i}).INC.max;
    avg_pwr(i) = data_struct.(event_name{i}).INC.avg.INC_avg;
    pk_tra(i) = max(data_struct.(event_name{i}).TRA.data_cal);
    ft_end = 462; %change it if pulse length changes from nominal
    if data_struct.(event_name{i}).tuning.fail_m2 ~= true
        tuning_slope(i) = data_struct.(event_name{i}).tuning.slope;
        tuning_delta(i) = getDeltaPower(tuning_slope(i),...
            data_struct.(event_name{i}).tuning.x1,ft_end);
    else 
        tuning_slope(i) = NaN;
        tuning_delta(i) = NaN;
        failSlope = failSlope+1;
        failDelta = failDelta+1;
    end
    if data_struct.(event_name{i}).tuning.fail_m1 ~= true
        top_len(i) = 4e-9*(data_struct.(event_name{i}).tuning.top.x2 - data_struct.(event_name{i}).tuning.top.x1);
        mid_len(i) = 4e-9*(data_struct.(event_name{i}).tuning.mid.x2 - data_struct.(event_name{i}).tuning.mid.x1);
        bot_len(i) = 4e-9*(data_struct.(event_name{i}).tuning.bot.x2 - data_struct.(event_name{i}).tuning.bot.x1);
    else
        top_len(i) = NaN;
        mid_len(i) = NaN;
        bot_len(i) = NaN;
        fail_m1 = fail_m1+1;
    end
end


%% Start the filtering 
% filling bool arrays
    [hasBeam,~,~] = beamCheck(bpm1_ch, bpm1_thr, bpm2_ch, bpm2_thr,'bpm1');
% filling event arrays    
    %w/ and w/o beam
    Beam = event_name(hasBeam);
    noBeam = event_name(~hasBeam);

    
%% Parameters check plots 
%Get screen parameters in order to resize the plots
% screensizes = get(groot,'screensize'); %only MATLAB r2014b+
% screenWidth = screensizes(3);
% screenHeight = screensizes(4);
% winW = screenWidth/2;
% winH = screenHeight/2;
winW = 1420;
winH = 760;
%Calculate the timescale for the x of the charge plot
xscale = zeros(1,length(ts_array));
ts_array_vec = datevec(ts_array); 
for k=1:length(ts_array)
    xscale(k) = etime(ts_array_vec(k,:),ts_array_vec(1,:));
end
xscale = xscale/60; %in minutes
%Charge time distribution plot
f1 = figure('position',[0 0 winW winH]);
figure(f1)
subplot(2,1,1)
plot(xscale, bpm1_ch,'.','MarkerSize',12);
line(xlim, [bpm1_thr bpm1_thr], 'Color', 'r','LineWidth',1) %horizontal line
title('BPM1 charge distribution')
xlabel('Minutes')
ylabel('Integrated charge')
legend({'Acquisition','threshold'},'Position',[.825 .825 .065 .065])
subplot(2,1,2)
plot(xscale,bpm2_ch,'.','MarkerSize',12)
line(xlim, [bpm2_thr bpm2_thr], 'Color', 'r','LineWidth',1) %horizontal line
title('BPM2 charge distribution')
xlabel('Minutes')
ylabel('Integrated charge')
ylim([min(bpm2_ch)-5 5])
legend({'Interlocks','threshold'},'Position',[.825 .35 .065 .065])
path1 = [datapath_write_plot filesep fileName '_charge_distribution'];
print(f1,path1,'-djpeg')
savefig(path1)
%TRA time distribution plot
f2 = figure('position',[0 0 winW winH]);
figure(f2)
plot(xscale(hasBeam), pk_tra(hasBeam),'.','MarkerSize',20);
hold on
plot(xscale(~hasBeam), pk_tra(~hasBeam),'.','MarkerSize',20);
hold off
title('TRA peak power distribution in time')
xlabel('Minutes')
ylabel('SDtructure output Power (W)')
legend({'With beam','Without Beam'},'Position',[.15 .8 .085 .085])
path2 = [datapath_write_plot filesep fileName '_TRA_peak_vs_time'];
print(f2,path2,'-djpeg')
savefig(path2)
%INC time distribution plot
f3 = figure('position',[0 0 winW winH]);
figure(f3)
plot(xscale(hasBeam), pk_pwr(hasBeam),'.','MarkerSize',20);
hold on
plot(xscale(~hasBeam), pk_pwr(~hasBeam),'.','MarkerSize',20);
hold off
title('TRA peak power distribution in time')
xlabel('Minutes')
ylabel('SDtructure output Power (W)')
legend({'With beam','Without Beam'},'Position',[.15 .8 .085 .085])
path3 = [datapath_write_plot filesep fileName '_INC_peak_vs_time'];
print(f3,path3,'-djpeg')
savefig(path3)
%TUNING time distribution plot
f4 = figure('position',[0 0 winW winH]);
figure(f4)
plot(xscale(hasBeam), tuning_delta(hasBeam),'.','MarkerSize',20);
hold on
plot(xscale(~hasBeam), tuning_delta(~hasBeam),'.','MarkerSize',20);
hold off
title('Pulse tuning distribution in time')
xlabel('Minutes')
ylabel('Power difference (W)')
legend({'With beam','Without Beam'},'Position',[.15 .8 .085 .085])
path4 = [datapath_write_plot filesep fileName '_tuning_vs_time'];
print(f4,path4,'-djpeg')
savefig(path4)
    
%% Report message part 2
disp('Analysis done! ')
%open the log file and append
logID = fopen([datapath_write filesep savename '.log'], 'a' ); 
%gather data and build the message
%%INTO THE METRIC
l1 = length(Beam);
l2 = length(noBeam);
msg2 = ['Overall number of normal pulses: ' num2str(l1+l2) ' of which :' '\n' ...
' - ' num2str(l1) ' are with beam' '\n' ...
' - ' num2str(l2) ' are without beam' '\n' ...
];

% print to screen (1) and to log file
fprintf(1,msg2);
fprintf(logID,msg2);
fclose(logID);

%% Distributions plots
% Probability plot
f5 = figure('position',[0 0 winW winH]);
figure(f5)
xbins = 0:0.2e16:2e16;
histogram(prob(hasBeam),xbins);
hold on
histogram(prob(~hasBeam),xbins);
legend({'With beam','Without beam'},'Position',[.15 .8 .085 .085])
xlabel('$$ \int P^3 d \tau $$','interpreter','latex')
ylabel('Counts')
title('BD probability')
path5 = [datapath_write_plot filesep fileName '_BD_probability'];
print(f5,path5,'-djpeg')
savefig(path5)
% peak TRA power distribution
f6 = figure('position',[0 0 winW winH]);
figure(f6)
xbins = linspace(0,round(max(pk_tra),-6),(1e-6*round(max(pk_tra),-6)+1));
h1 = hist(pk_tra(hasBeam),xbins);
h2 = hist(pk_tra(~hasBeam),xbins);
bar([h1;h2]','stack')
legend({'With Beam','Without Beam'},'Position',[.15 .8 .085 .085])
xlabel('Power (MW)')
ylabel('Counts')
title('Overall distribution of peak transmitted power for backup events')
path6 = [datapath_write_plot filesep fileName '_peak_TRA_power_distribution'];
print(f6,path6,'-djpeg')
savefig(path6)
% tuning delta power distribution
f7 = figure('position',[0 0 winW winH]);
figure(f7)
subplot(2,1,1)
tmp_tuning = tuning_delta;
xbins = linspace(-20e6,20e6,41); %1M per bin
histogram(tmp_tuning(hasBeam),xbins)
title('Backup pulses tuning distribution: pulses with beam')
xlabel('Power delta (W)')
ylabel('Counts')
subplot(2,1,2)
tmp_tuning = tuning_delta;
xbins = linspace(-20e6,20e6,41); %1M per bin
histogram(tmp_tuning(~hasBeam),xbins)
title('Backuo pulses tuning distribution: pulses without beam ')
xlabel('Power delta (W)')
ylabel('Counts')
path7 = [datapath_write_plot filesep fileName '_tuning_delta_power_distribution'];
print(f7,path7,'-djpeg')
savefig(path7)
%pulse length
f8 = figure('position',[0 0 winW winH]);
figure(f8)
subplot(2,1,1)
top_tmp = top_len(hasBeam);
mid_tmp = mid_len(hasBeam);
bot_tmp = bot_len(hasBeam);
xbins = 0:4:(round(max(bot_len)*1e9)+2);
histogram(top_tmp*1e9,xbins);
title('Pulse width at various heights for backup pulses with beam')
hold on
histogram(mid_tmp*1e9,xbins);
hold on
histogram(bot_tmp*1e9,xbins);
l = legend({'85%','65%','40%'},'Position',[.15 .8 .085 .085]);
xlabel('Pulse width (ns)')
ylabel('Counts')
hold off
subplot(2,1,2)
top_tmp = top_len(~hasBeam);
mid_tmp = mid_len(~hasBeam);
bot_tmp = bot_len(~hasBeam);
xbins = 0:4:(round(max(bot_len)*1e9)+2);
histogram(top_tmp*1e9,xbins);
title('Pulse width at various heights for backup pulses without beam')
hold on
histogram(mid_tmp*1e9,xbins);
hold on
histogram(bot_tmp*1e9,xbins);
l = legend({'85%','65%','40%'},'Position',[.15 .8 .085 .085]);
xlabel('Pulse width (ns)')
ylabel('Counts')
hold off
path8 = [datapath_write_plot filesep fileName '_pulse_width_distribution'];
print(f8,path8,'-djpeg')
savefig(path8)
% peak INC power distribution
f9 = figure('position',[0 0 winW winH]);
figure(f9)
xbins = linspace(0,round(max(pk_pwr),-6),(1e-6*round(max(pk_pwr),-6)+1));
h1 = hist(pk_pwr(hasBeam),xbins);
h2 = hist(pk_pwr(~hasBeam),xbins);
bar([h1;h2]','stack')
legend({'With Beam','Without Beam'},'Position',[.15 .8 .085 .085])
xlabel('Power (MW)')
ylabel('Counts')
title('Overall distribution of peak incident power for backup events')
path9 = [datapath_write_plot filesep fileName '_peak_power_distribution'];
print(f9,path9,'-djpeg')
savefig(path9)
% average INC power distribution
f10 = figure('position',[0 0 winW winH]);
figure(f10)
xbins = linspace(0,round(max(pk_pwr),-6),(1e-6*round(max(pk_pwr),-6)+1)); %1MW per bin
h1 = hist(avg_pwr(hasBeam),xbins);
h2 = hist(avg_pwr(~hasBeam),xbins);
bar([h1;h2]','stack')
legend({'With Beam','Without Beam'},'Position',[.15 .8 .085 .085])
xlabel('Power (MW)')
ylabel('Counts')
title('Overall distribution of average incident power for backup events')
path10 = [datapath_write_plot filesep fileName '_average_power_distribution'];
print(f10,path10,'-djpeg')
savefig(path10)

%% Create tex file
%adjust date format
sdate = data_struct.Props.startDate;
sdatenum = datenum(sdate,'yyyymmdd');
sdatestr = datestr(sdatenum,'yyyy mmm dd');

edate = data_struct.Props.endDate;
edatenum = datenum(edate,'yyyymmdd');
edatestr = datestr(edatenum,'yyyy mmm dd');
%get number of pulses
l1 = length(Beam);
l2 = length(noBeam);
%create the file
texID = createTex(datapath_write,savename,'Normal run report', ...
    sdatestr, data_struct.Props.startTime, edatestr, data_struct.Props.endTime,...
    datestr(datetime('now')),...
    fileName, bpm1_thr, bpm2_thr,...
    l1,l2...
    );

addPlotTex(datapath_write,savename,path1,'jpg');
addPlotTex(datapath_write,savename,path2,'jpg');
addPlotTex(datapath_write,savename,path3,'jpg');
addPlotTex(datapath_write,savename,path4,'jpg');
addPlotTex(datapath_write,savename,path5,'jpg');
addPlotTex(datapath_write,savename,path6,'jpg');
addPlotTex(datapath_write,savename,path7,'jpg');
addPlotTex(datapath_write,savename,path8,'jpg');
addPlotTex(datapath_write,savename,path9,'jpg');
addPlotTex(datapath_write,savename,path10,'jpg');

closeTex(datapath_write,savename);