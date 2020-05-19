% set data parameters
statDist = 10000;
t0 = 5.5;
f_max = 0.5;
t_max = 125;
t = 1/(2*f_max):1/(2*f_max):t_max;
nt = t_max*(2*f_max);

% set flag for toy problem
test = 0;

% get real data
fname = "/media/Data/Data/PIG/MSEED/noIR/PIG2/HHZ/2012-04-02.PIG2.HHZ.noIR.MSEED";
dataStruct = rdmseed(fname);

% extract trace
trace = extractfield(dataStruct,'d');
fs = 100;

% resample data to 1 Hz
fsNew = f_max*2;
trace = resample(trace,fsNew,100);

% set event bounds
startTime = ((15*60+18)*60+50)*fsNew;
endTime = startTime + nt;

% trim data to event bounds
eventTrace = trace(startTime:endTime-1);

% remove scalar offset using first value
eventTrace = eventTrace - eventTrace(1);

% if toy problem mode, set waveform to recover
if test
    testParams = [450,600,statDist,t0,f_max,t_max];
    [eventTrace,~] = GF_func_mcmc(testParams,eventTrace);
end

% find index of max value
[~,dataMaxIdx] = max(eventTrace);

% set mcmc parameters
% x0 goes like this: [h_i,h_w,statDist,t0,f_max,t_max,dataMaxIdx]
% f_max, t_max, and dataMaxIdx MUST have 0 step size in xStep
x0 = [75,475,4950,5.35,0.5,t_max];
xStepVect = {[10,10,0,0,0,0]};
xBounds = [0,1000;
           0,1000;
           0,100000;
           0,10;
           0,f_max+1;
           0,t_max+1;];
sigmaVect = [4];
numIt = 10000;
L_type = "modified";
axisLabels = ["Ice thickness (m)", "Water depth (m)", "X_{stat} (m)","t_0 (s)"];
paramLabels = ["h_i","h_w","Xstat","t0"];

try
    parpool;
    poolobj = gcp;
catch
    fprintf("Using existing parpool...\n")
end

tic;

parfor p = 1:length(sigmaVect)
        
    % get parameters for run
    xStep = xStepVect{p};
    sigma = sigmaVect(p);
    
    % record which two parameters will be varied this run
    paramInd = [1,2,3,4,5,6]
    paramsVaried = paramInd(xStep ~= 0);
    
    % generate intial Green's function
    [G_0,eventAlign,M_frac_0] = GF_func_mcmc(x0,eventTrace);

    % calculate initial liklihood
    L0 = liklihood(G_0,eventAlign,sigma,L_type);
    
    % run mcmc
    [x_keep,L_keep,count,alpha_keep,accept,M_frac] = mcmc('GF_func_mcmc',eventTrace,...
                                              x0,xStep,xBounds,sigma,numIt,L0,L_type);

    % give output
    fprintf("Accepted " + round((sum(accept)/numIt)*100) + " %% of proposals\n");
    
    % make plots for bivariate runs
    if length(paramsVaried) == 2

        % find best-fit parameters using 2D histogram
        numBins = length(unique(x_keep(paramsVaried(1),:)));
        if numBins > 200
            numBins = 200
        end
        [density,coords] = hist3([x_keep(paramsVaried(1),:)',x_keep(paramsVaried(2),:)'],[numBins,numBins]);
        [var1_ind,var2_ind] = ind2sub(size(density),find(density == max(density,[],'all')));
        xFit = x0;
        xFit(paramsVaried(1)) = coords{1}(var1_ind(1));
        xFit(paramsVaried(2)) = coords{2}(var2_ind(1));   

        % run model for best fit parameters
        [G_fit,eventAlign,M_frac_fit] = GF_func_mcmc(xFit,eventTrace);

        % calculate solution liklihood
        L_fit = liklihood(G_fit,eventAlign,sigma,L_type);

        % call plotting functions
        plot_bivar(x_keep,xFit,numIt,p,paramsVaried,axisLabels,paramLabels)
        plot_M_frac(x_keep,M_frac,xFit,numIt,p,paramsVaried,axisLabels,paramLabels)
        plot_start_wave(t,eventAlign,sigma,L0,M_frac_0,G_0,x0,numIt,xStep,p)
        plot_fit_wave(t,eventAlign,sigma,L_fit,M_frac_fit,G_0,xFit,numIt,xStep,accept,p)
    
    else
        fprintf("Not yet supported\n")
    end
    
end

runtime = toc;