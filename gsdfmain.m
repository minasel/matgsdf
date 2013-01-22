% This script is used to measure the phase difference between nearby stations. 
% The input format is eventmat format, which is a matlab structure includes:
% struct event:
%   * string: eventid
%   * string: otimestr
%   * float otime
%   * float evla
%   * float evlo
%   * struct[] stadata
%      * stla
%      * stlo
%      * staotime
%      * delta
%      * data
%      * string comp

clear;

isdebug = 1;
is_overwrite = 1;

eventmatpath = './eventmat/';
CSoutputpath = './CSmeasure/';

if ~exist(CSoutputpath,'dir')
	mkdir(CSoutputpath)
end

% Setup parameters
setup_parameters

% Setup Error Codes for Bad data
setup_ErrorCode

parameters.periods = sort(parameters.periods);  % make sure periods are ascending
periods = parameters.periods;
minstadist = parameters.minstadist;
maxstadist = parameters.maxstadist;

matfiles = dir([eventmatpath,'/*.mat']);
for ie = 1:length(matfiles)
%for ie = 100
    
	clear event eventcs CS
	% read in the events information
	temp = load([eventmatpath,matfiles(ie).name]);
	event = temp.event;

	matfilename = [CSoutputpath,char(event.id),'_cs.mat'];
	if ~is_overwrite && exist(matfilename,'file')
		disp(['Found ',matfilename,', skip this event!']);
		continue;
	end
	disp(['Start to work on event: ',event.id]);

	% set up some useful arrays
	stlas = [event.stadata(:).stla];
	stlos = [event.stadata(:).stlo];
	stnms = {event.stadata(:).stnm};
	dists = [event.stadata(:).dist];

	% check whether the stations are in the range
	for ista = 1:length(event.stadata)
		event.stadata(ista).isgood = 1;
		if ~Is_inrange(stlas(ista),stlos(ista),parameters)
			event.stadata(ista).isgood = ErrorCode.sta_outofrange;
		end
	end


	% automatically select the signal window by using ftan method
	winpara = auto_win_select(event,periods);
    plot_win_select(event,periods,winpara);
	if length(winpara) ~= 4
		continue;
	end
	v1 = winpara(1); t1=winpara(2); v2=winpara(3); t2=winpara(4);
	event.winpara = winpara;

	% Calculate Auto-correlation
	disp(['Calculating the auto-correlation of each station'])
	for ista = 1:length(event.stadata)
		event.stadata(ista).isgood = 1;
		autocor = CS_measure(event,ista,ista,parameters);
		if ~isfield(autocor,'amp')
			disp(['Station: ',event.stadata(ista).stnm,' doesn''t have enough data for this event!']);
			event.stadata(ista).isgood = ErrorCode.sta_lackdata;
			event.autocor(ista).sta1 = ista;
		else
			event.autocor(ista) = autocor;
		end
	end
	

	% start to find nearby stations and apply cross-correlation measurement
	csnum = 0;
	disp(['Calculating cross-correlation between stations'])
	for ista = 1:length(event.stadata)
		if event.stadata(ista).isgood < 0;
			continue;
		end
		% Find nearby stations
		stadist = deg2km(distance(stlas(ista),stlos(ista),stlas,stlos));
		nbstaids = find(stadist > minstadist & stadist < maxstadist);
		for nbsta = nbstaids
			if nbsta > ista && event.stadata(nbsta).isgood > 0
				% Build up Cross-Station Measurement structure
				csnum = csnum+1;
				if mod(csnum,10) == 0
					disp(csnum);
				end
				CS(csnum) = CS_measure(event,ista,nbsta,parameters);
			end % end of nbsta > ista
		end % end of nearby station loop
	end % end of station loop

	% Calculate the coherency between each station pairs
	for ics = 1:length(CS)
		sta1 = CS(ics).sta1;
		sta2 = CS(ics).sta2;
		for ip=1:length(periods)
			CS(ics).cohere(ip) = CS(ics).amp(ip)^2/event.autocor(sta1).amp(ip)/event.autocor(sta2).amp(ip);
		end
	end

	%% Data Quality Control
	%
	for ics = 1:length(CS)
		for ip = 1:length(periods)
			CS(ics).isgood(ip) = 1;
		end
	end

	% Remove measurements having fitting error
	for ics = 1:length(CS)
		for ip = 1:length(periods)
			if CS(ics).exitflag(ip) < 0
				CS(ics).isgood(ip) = ErrorCode.cs_fit_error;
			end
			if event.autocor(CS(ics).sta1).exitflag(ip) < 0
				CS(ics).isgood(ip) = ErrorCode.sta_fit_error;
			end
			if event.autocor(CS(ics).sta2).exitflag(ip) < 0
				CS(ics).isgood(ip) = ErrorCode.sta_fit_error;
			end
		end
	end
	% Remove measurements having low coherency
	for ics = 1:length(CS)
		for ip = 1:length(periods)
			if CS(ics).cohere(ip) < parameters.cohere_tol
				CS(ics).isgood(ip) = ErrorCode.low_cohere;
			end
		end
	end
	% Get average phase velocity across the array and remove the outliers.
	clear avgphv
	for ip=1:length(periods)
		clear ddist dtp isgood
		for ics = 1:length(CS)
			ddist(ics) = CS(ics).ddist;
			dtp(ics) = CS(ics).dtp(ip);
			isgood(ics) = CS(ics).isgood(ip);
		end % end of ics
		goodind = find(isgood > 0);
		para = polyfit(ddist(goodind),dtp(goodind),1);
		err = abs(ddist*para(1) + para(2) - dtp);
		for ics = 1:length(CS)
			if err(ics) > parameters.tp_tol && CS(ics).isgood(ip) > 0
				CS(ics).isgood(ip) = ErrorCode.high_tp_err;
			end
			isgood(ics) = CS(ics).isgood(ip);
		end
		goodind = find(isgood > 0);
		para = polyfit(ddist(goodind),dtp(goodind),1);
		avgphv(ip) = 1./para(1);
	end % end of periods

	% create eventcs structure and output
	eventcs.CS = CS;
	eventcs.id = event.id;
	eventcs.avgphv = avgphv;
	eventcs.stlas = stlas;
	eventcs.stlos = stlos;
	eventcs.stnms = stnms;
	eventcs.evla = event.evla;
	eventcs.evlo = event.evlo;
	eventcs.dists = dists;
	eventcs.eventmatfile = [eventmatpath,matfiles(ie).name];

	matfilename = [CSoutputpath,char(event.id),'_cs'];
	save(matfilename,'eventcs')
	disp(['Save to ',matfilename]);
end % end of ie loop
