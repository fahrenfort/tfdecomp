function [tf_cluststat] = tfclustperm_tf(cfg,tfdata,varargin)

v2struct(cfg);

% ingredients from cfg

% a few defaults
if ~isfield(cfg,'plot_output')
    plot_output = 'no';
end
if ~isfield(cfg,'pval')
    pval = 0.05;
end
if ~isfield(cfg,'conn')
    conn = 8;
end
if ~isfield(cfg,'nperm')
    nperm = 2000;
end
if ~isfield(cfg,'test_statistic')
    test_statistic = 'sum';
end
if ~isfield(cfg,'avgoverfreq')
    avgoverfreq = 'no';
end
% if isfield(cfg,'mask')
%     chan = mask.cfg_prev.chan;
% end
ntests = 1;

% select channels
chan2test=[];
for ch=1:length(chan)
    chan2test(ch) = find(strcmpi({dim.chans.labels},chan(ch)));
end

if isfield(cfg,'chandiff')
    chan2test2=[];
    for ch=1:length(chandiff)
        chan2test2(ch) = find(strcmpi({dim.chans.labels},chandiff(ch)));
    end
    X1 = squeeze(mean(tfdata(:,chan2test,:,:),2) - mean(tfdata(:,chan2test2,:,:),2));
else
    X1 = squeeze(mean(tfdata(:,chan2test,:,:),2));
end

% if third argument, this means condition comparison
if ~isempty(varargin)
    if isfield(cfg,'chandiff')
        X2 = squeeze(mean(varargin{1}(:,chan2test,:,:),2) - mean(varargin{1}(:,chan2test2,:,:),2));
    else
        X2 = squeeze(mean(varargin{1}(:,chan2test,:,:),2));
    end
    X = X1-X2;
else
    X = X1;
end

if ~strcmp(cfg.toi,'all');
    toi = dsearchn(dim.times',cfg.toi')';toi=toi(1):toi(2);
else
    toi=1:length(dim.times);
end

if isfield(cfg,'foi')
    if ~strcmp(cfg.foi,'all');
        foi = dsearchn(dim.freqs',cfg.foi')';foi=foi(1):foi(2);
    else
        foi=1:length(dim.freqs);
    end
else
    foi=1:length(dim.freqs);
end

tftime = dim.times(toi);
tffrex = dim.freqs(foi);

X  = X(:,foi,toi);
X1 = X1(:,foi,toi);
if ~isempty(varargin)
    X2 = X2(:,foi,toi);
end

% if requested, average over frequency domain to do time-domain test
if strcmp(avgoverfreq,'yes');
    X = mean(X,2);
    X1 = mean(X1,2);
    if ~isempty(varargin)
        X2 = mean(X2,2);
    end
elseif isfield(cfg,'mask')
    fprintf('Averaging over frequency based on statistical mask...\n')
    avgoverfreq = 'yes';
    clusts = bwconncomp(mask.tmapthresh);
    fprintf('Found %i freq-bands from clusters...\n',clusts.NumObjects);
    binmask = zeros(size(mask.tmapthresh(:)));
    for clusti=1:clusts.NumObjects
        binmask(clusts.PixelIdxList{clusti})=clusti;
    end
    binmask=reshape(binmask,clusts.ImageSize);
    ntests = clusts.NumObjects;
end

% backup for multiple tests
origX = X;
if ~isempty(varargin)
    origX1 = X1;
    origX2 = X2;
end

for testi=1:ntests
    
    if isfield(cfg,'mask')
        freqmask = zeros(1,length(dim.freqs));
        for fi=1:length(dim.freqs)
            freqmask(fi) = mean(mask.tmapthresh(fi,binmask(fi,:)==testi));
        end
        foi = find(abs(freqmask)>nanmedian(abs(freqmask))+.5*nanstd(abs(freqmask)));
        cfg.foi = [dim.freqs(foi(1)) dim.freqs(foi(end))];
        fprintf('Selected %s - %s Hz...\n',num2str(round(dim.freqs(foi(1))*10)/10),num2str(round(dim.freqs(foi(end))*10)/10))
        X = mean(origX(:,foi,:),2);
        if ~isempty(varargin)
            X1 = mean(origX1(:,foi,:),2);
            X2 = mean(origX2(:,foi,:),2);
        end
    end
    nSubjects = size(tfdata,1);
    voxel_pval   = pval;
    cluster_pval = pval;

    % initialize null hypothesis matrices
    max_clust_info   = zeros(nperm,1);
    
    %% real t-values
    
    [~,~,~,tmp] = ttest(X);
    tmap = squeeze(tmp.tstat);
    
    realmean = squeeze(mean(X));
    
    % uncorrected pixel-level threshold
    threshmean = realmean;
    tmapthresh = tmap;
    if ~isfield(cfg,'tail')
        tmapthresh(abs(tmap)<tinv(1-voxel_pval/2,nSubjects-1))=0;
        threshmean(abs(tmap)<tinv(1-voxel_pval/2,nSubjects-1))=0;
    elseif strcmp(tail,'left')
        tmapthresh(tmap>-1.*tinv(1-voxel_pval,nSubjects-1))=0;
        threshmean(tmap>-1.*tinv(1-voxel_pval,nSubjects-1))=0;
    elseif strcmp(tail,'right')
        tmapthresh(tmap<tinv(1-voxel_pval,nSubjects-1))=0;
        threshmean(tmap<tinv(1-voxel_pval,nSubjects-1))=0;
    end
    
    %%
    fprintf('Performing %i permutations:\n',nperm);
    
    for permi=1:nperm
        
        if mod(permi,100)==0, fprintf('..%i\n',permi); end
        
        clabels = logical(sign(randn(nSubjects,1))+1);
        tlabels = logical(sign(randn(nSubjects,1))+1);
        flabels = logical(sign(randn(nSubjects,1))+1);
        
        temp_permute = X; % X is the data structure and is assumed to be a difference score
        temp_permute(clabels,:,:)=temp_permute(clabels,:,:)*-1;
        
        %% permuted t-maps
        [~,~,~,tmp] = ttest(squeeze(temp_permute));
        
        faketmap = squeeze(tmp.tstat);
        if ~isfield(cfg,'tail')
            faketmap(abs(faketmap)<tinv(1-voxel_pval/2,nSubjects-1))=0;
        elseif strcmp(tail,'left')
            faketmap(faketmap>-1.*tinv(1-voxel_pval,nSubjects-1))=0;
        elseif strcmp(tail,'right')
            faketmap(faketmap<tinv(1-voxel_pval,nSubjects-1))=0;
        end
        
        % get number of elements in largest supra-threshold cluster
        clustinfo = bwconncomp(faketmap,conn);
        if strcmp(test_statistic,'count')
            max_clust_info(permi) = max([ 0 cellfun(@numel,clustinfo.PixelIdxList) ]); % the zero accounts for empty maps; % using cellfun here eliminates the need for a slower loop over cells
        elseif strcmp(test_statistic,'sum')
            tmp_clust_sum = zeros(1,clustinfo.NumObjects);
            for ii=1:clustinfo.NumObjects
                tmp_clust_sum(ii) = sum(abs(faketmap(clustinfo.PixelIdxList{ii})));
            end
            if  clustinfo.NumObjects>0, max_clust_info(permi) = max(tmp_clust_sum); end
        else
            error('Absent or incorrect test statistic input!');
        end
        
    end
    fprintf('..Done!\n');
    
    %% apply cluster-level corrected threshold
    
    % find islands and remove those smaller than cluster size threshold
    clustinfo = bwconncomp(tmapthresh,conn);
    if strcmp(test_statistic,'count')
        clust_info = cellfun(@numel,clustinfo.PixelIdxList); % the zero accounts for empty maps; % using cellfun here eliminates the need for a slower loop over cells
    elseif strcmp(test_statistic,'sum')
        clust_info = zeros(1,clustinfo.NumObjects);
        for ii=1:clustinfo.NumObjects
            clust_info(ii) = sum(abs(tmapthresh(clustinfo.PixelIdxList{ii})));
        end
    end
    clust_threshold = prctile(max_clust_info,100-cluster_pval*100);
    
    % identify clusters to remove
    whichclusters2remove = find(clust_info<clust_threshold);
    
    % compute p-n value for all clusters
    clust_pvals = zeros(1,length(clust_info));
    clust_act = clust_pvals;
    for cp=1:length(clust_info)
        clust_pvals(cp) = length(find(max_clust_info>clust_info(cp)))/nperm;
        clust_act(cp) = sum(tmapthresh(clustinfo.PixelIdxList{cp}));
    end
    
    % remove clusters
    for i=1:length(whichclusters2remove)
        tmapthresh(clustinfo.PixelIdxList{whichclusters2remove(i)})=0;
    end
    
    %% Generate figure: time-freq
    
    if strcmp(plot_output,'yes') && strcmp(avgoverfreq,'no');
        figure
        
        subplot(221)
        contourf(tftime,tffrex,squeeze(tmap),40,'linecolor','none')
        cmax=max(abs(get(gca,'clim')));
        axis square
%         set(gca,'clim',[-cmax cmax],'yscale','log','ytick',[round(logspace(log10(min(tffrex)),log10(max(tffrex)),5))] )
        set(gca,'clim',[-cmax cmax],'ytick',[round(linspace((min(tffrex)),(max(tffrex)),5))] )
        title('unthresholded t-map')
        xlabel('Time (ms)'), ylabel('Frequency (Hz)')
        
        subplot(222)
        topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test,'o','k',5,1},'whitebk','on')
        if isfield(cfg,'chandiff')
            hold on
            topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test2,'o','r',5,1},'whitebk','on')
        end
        
        subplot(223)
        contourf(tftime,tffrex,realmean,40,'linecolor','none')
        cmax=max(abs(get(gca,'clim')));
        axis square
        hold on
        contour(tftime,tffrex,abs(threshmean)>0,1,'k');
%         set(gca,'clim',[-cmax cmax],'yscale','log','ytick',[round(logspace(log10(min(tffrex)),log10(max(tffrex)),5))] )
        set(gca,'clim',[-cmax cmax],'ytick',[round(linspace((min(tffrex)),(max(tffrex)),5))] )
        title('Uncorrected power map')
        xlabel('Time (ms)'), ylabel('Frequency (Hz)')
        
        subplot(224)
        contourf(tftime,tffrex,tmapthresh,40,'linecolor','none')
        cmax=max(abs(get(gca,'clim')));
        axis square
%         set(gca,'clim',[-cmax cmax],'yscale','log','ytick',[round(logspace(log10(min(tffrex)),log10(max(tffrex)),5))] )
        set(gca,'clim',[-cmax cmax],'ytick',[round(linspace((min(tffrex)),(max(tffrex)),5))] )
        title('Cluster-corrected t-map')
        xlabel('Time (ms)'), ylabel('Frequency (Hz)')
    end
    
    %% Generate figure: time
    
    if strcmp(plot_output,'yes') && strcmp(avgoverfreq,'yes');
        figure
        
        if ~isempty(varargin)
            
            subplot(221)
            topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test,'o','k',5,1},'whitebk','on')
            if isfield(cfg,'chandiff')
                hold on
                topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test2,'o','r',5,1},'whitebk','on')
            end
            
            subplot(223)
            [l,p] = boundedline(tftime,squeeze(mean(X1)),squeeze(std(X1))./sqrt(nSubjects),'b','alpha','transparency',.1);
            outlinebounds(l,p);
            h(1)=l;
            [l,p] = boundedline(tftime,squeeze(mean(X2)),squeeze(std(X1))./sqrt(nSubjects),'r','alpha','transparency',.1);
            outlinebounds(l,p);
            h(2)=l;
            legend(h,'conA','conB');
            yl=get(gca,'ylim');
            
            axis square
            title('Conditions')
            xlabel('Time (ms)'), ylabel('Raw activity')
            
            hold on
            plotclust = bwconncomp(threshmean,conn);
            for blob=1:plotclust.NumObjects;
                plot([tftime(plotclust.PixelIdxList{blob}(1)) tftime(plotclust.PixelIdxList{blob}(end))],[min(yl)+sum(abs(yl))/20 min(yl)+sum(abs(yl))/20],'color',[.5 .5 .5],'linewidth',4);
            end
            
            subplot(224)
            [l,p] = boundedline(tftime,squeeze(mean(X)), squeeze(std(X)) ./sqrt(nSubjects),'b','alpha','transparency',.1);
            outlinebounds(l,p);
            axis square
            title('Difference')
            xlabel('Time (ms)'), ylabel('T-val')
            
            hold on
            plotclust = bwconncomp(tmapthresh,conn);
            for blob=1:plotclust.NumObjects;
                plot([tftime(plotclust.PixelIdxList{blob}(1)) tftime(plotclust.PixelIdxList{blob}(end))],[min(yl)+sum(abs(yl))/20 min(yl)+sum(abs(yl))/20],'k','linewidth',4);
            end
        else
            
            subplot(121)
            topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test,'o','k',5,1},'whitebk','on')
            if isfield(cfg,'chandiff')
                hold on
                topoplot(zeros(1,length(dim.chans)),dim.chans,'electrodes','off','emarker2',{chan2test2,'o','r',5,1},'whitebk','on')
            end
            
            subplot(122)
            [l,p] = boundedline(tftime,squeeze(mean(X)),squeeze(std(X))./sqrt(nSubjects),'k','alpha','transparency',.1);
            outlinebounds(l,p);
            axis square
            title('Single condition')
            xlabel('Time (ms)'), ylabel('T-val')
            yl=get(gca,'ylim');

            hold on
            plotclust = bwconncomp(threshmean,conn);
            for blob=1:plotclust.NumObjects;
                plot([tftime(plotclust.PixelIdxList{blob}(1)) tftime(plotclust.PixelIdxList{blob}(end))],[min(yl)+sum(abs(yl))/10 min(yl)+sum(abs(yl))/10],'color',[.5 .5 .5],'linewidth',4);
            end
            hold on
            plotclust = bwconncomp(tmapthresh,conn);
            for blob=1:plotclust.NumObjects;
                plot([tftime(plotclust.PixelIdxList{blob}(1)) tftime(plotclust.PixelIdxList{blob}(end))],[min(yl)+sum(abs(yl))/20 min(yl)+sum(abs(yl))/20],'k','linewidth',4);
            end
            
        end
        
    end
    if isfield(cfg,'cmap')
        if ischar(cmap)
            colormap({cmap})
        else
            colormap(cmap)
        end
    end
    
    %% output
    
    tf_cluststat(testi).realmap = realmean;
    tf_cluststat(testi).subjmap.diff = X;
    if ~isempty(varargin)
        tf_cluststat(testi).subjmap.conA = X1;
        tf_cluststat(testi).subjmap.conB = X2;
    end
    tf_cluststat(testi).tmap = tmap;
    tf_cluststat(testi).threshmean = threshmean;
    tf_cluststat(testi).tmapthresh = tmapthresh;
    tf_cluststat(testi).time = tftime;
    tf_cluststat(testi).freq = tffrex;
    [tf_cluststat(testi).pvals,idx] = sort(clust_pvals,2,'ascend'); % gives the cluster with lowest p-value first
    tf_cluststat(testi).clustinfo = clust_act(idx);
    tf_cluststat(testi).cfg_prev = cfg;
end
end