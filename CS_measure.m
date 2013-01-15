function CS = CS_measure(event,sta1,sta2,parameters)
% Main function to perform GSDF measurement

	refv = parameters.refv;
	periods = parameters.periods;
	min_width = parameters.min_width;
	max_width = parameters.max_width;
	wintaperlength = parameters.wintaperlength;
	prefilter = parameters.prefilter;
	xcor_win_halflength = parameters.xcor_win_halflength;
	Nfit = parameters.Nfit;
	isdebug = 0;

	v1 = event.winpara(1); t1=event.winpara(2); v2=event.winpara(3); t2=event.winpara(4);

	CS.sta1 = sta1;
	CS.sta2 = sta2;

	% read in data for station 1 and apply prefilter
	data1 = event.stadata(sta1).data;
	bgtime = event.stadata(sta1).otime - event.otime;
	dt1 = event.stadata(sta1).delta;
	Nt = length(event.stadata(sta1).data);
	fN = 1/2/dt1;
	[b,a] = butter(2,[1/prefilter(2)/fN, 1/prefilter(1)/fN]);
	data1 = filtfilt(b,a,data1);
	taxis1 = bgtime + [0:Nt-1]'*dt1;
	dist1 = event.stadata(sta1).dist;

	% read in data for station 2 and apply prefilter
	data2 = event.stadata(sta2).data;
	bgtime = event.stadata(sta2).otime - event.otime;
	dt2 = event.stadata(sta2).delta;
	Nt = length(event.stadata(sta2).data);
	fN = 1/2/dt2;
	[b,a] = butter(2,[1/prefilter(2)/fN, 1/prefilter(1)/fN]);
	data2 = filtfilt(b,a,data2);
	taxis2 = bgtime + [0:Nt-1]'*dt2;
	dist2 = event.stadata(sta2).dist;
	% resample the data if necessary
	if dt1 > dt2
		new_taxis2 = taxis2(1):dt1:taxis2(end);
		data2 = interp1(taxis2,data2,new_taxis2);
		taxis2 = new_taxis2;
		dt2 = dt1;
	elseif dt1 < dt2
		new_taxis1 = taxis1(1):dt2:taxis1(end);
		data1 = interp1(taxis1,data1,new_taxis1);
		taxis1 = new_taxis1;
		dt1 = dt2;
	end

	% window data2
	winbgt = dist2/v1+t1;
	winendt = dist2/v2+t2;
	win_data2 = flat_hanning_win(taxis2,data2,winbgt,winendt,wintaperlength);

	% apply cross-correlation
	[xcor,lag] = xcorr(data1,win_data2,10*max(periods)/dt1);
	lag = lag.*dt1;
	lag = lag + taxis1(1) - taxis2(1);

	if isdebug
		figure(43)
		clf
		subplot(3,1,1)
		plot(taxis1,data1);
		xlim([0 dist2/2])
		subplot(3,1,2)
		plot(taxis2,win_data2);
		xlim([0 dist2/2])
		subplot(3,1,3)
		plot(lag,xcor);
		xlim([-1000 1000])
	end

	%Find the window center (max amplitude within the window)
	win_cent_t = (dist1-dist2)/refv;
	search_win_ind = find( lag > win_cent_t-xcor_win_halflength &...
		lag < win_cent_t + xcor_win_halflength );
	[max_xcor_amp win_cent_i] = max(xcor(search_win_ind));
	win_cent_i = search_win_ind(win_cent_i);
	win_cent_t = lag(win_cent_i);
	CS.win_cent_t = win_cent_t;
	CS.ddist = dist1 - dist2;
	% apply the window function
	win_xcor = hanning_win(lag,xcor,win_cent_t,xcor_win_halflength*2);

	if isdebug
		figure(44)
		clf
		subplot(2,1,1)
		plot(lag,xcor);
		xlim([-500 500])
		subplot(2,1,2)
		plot(lag,win_xcor);
		xlim([-500 500])
	end

	% Apply Narrow-band filter
	clear gaus_filters nband_win_xcors
	Nt = length(win_xcor);
	[gaus_filters,faxis] = build_gaus_filter(1./periods,dt1,Nt,min_width,max_width);
	fft_win_xcor = fft(win_xcor);
	if size(fft_win_xcor) == 1
		fft_win_xcor = fft_win_xcor';
	end
	for ip = 1:length(periods)
		nband = fft_win_xcor .* [gaus_filters(:,ip); zeros(Nt-length(gaus_filters(:,ip)),1)];
		nband = ifft(nband);
		nband = 2*real(nband);
		nband_win_xcors(:,ip) = nband;
	end % end of periods loop

	if isdebug
		figure(45)
		clf
		[xi yi] = ndgrid(lag,periods);
		for ip = 1:length(periods)
			norm_nbands(:,ip) = nband_win_xcors(:,ip)./max(abs(nband_win_xcors(:,ip)));
		end
		contourf(xi,yi,norm_nbands);
		xlim([-3*max(periods) 3*max(periods)]);
	end

	% fitting with five-parameter wavelet
	for ip = 1:length(periods)
		[para,resnorm,residual, exitflag] = gsdffit(nband_win_xcors(:,ip),lag,1./periods(ip),Nfit);
		CS.fitpara(:,ip) = para(:);
		CS.fiterr(ip) = resnorm./para(1)^2./Nfit./periods(ip);
	end

end % end of function