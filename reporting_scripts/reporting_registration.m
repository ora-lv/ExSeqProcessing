function keys_total = reporting_registration(channels, registeredImagesDir, num_rounds, reportingDir)
%For every round,
% create a max projection of each registered image
% get the number of features
% save the 3D plots of feature agreements

save_types = {'fig','jpg'};
keys_total = [];

%Get the number of rounds and copy it out of the params variable
%because params is going to be overwritten when we load the Registation
%params
loadParameters;

if ~exist('channels', 'var')
    channels = params.CHAN_STRS;
end

if ~exist('registeredImagesDir', 'var')
    registeredImagesDir = params.registeredImagesDir;
end

if ~exist('num_rounds', 'var')
    num_rounds = params.NUM_ROUNDS;
end

if ~exist('reportingDir', 'var')
    reportingDir = params.reportingDir;
end

%reporting_getMaxProjections(registeredImagesDir, channels);


%Now calling code from the
loadExperimentParams;
figure('Visible','off');
for sequencing_round = 2:num_rounds
    
    % LOAD KEYS
    output_keys_filename = fullfile(registeredImagesDir,sprintf('globalkeys_%sround%.03i.mat',params.SAMPLE_NAME,sequencing_round));
    load(output_keys_filename);
    
    plot3(keyF_total(:,1),keyF_total(:,2),keyF_total(:,3),'o');
    hold on;
    for k_idx=1:size(keyF_total,1)
        plot3(keyM_total(k_idx,1),keyM_total(k_idx,2),keyM_total(k_idx,3),'ro');
        lines = [ ...
            [keyM_total(k_idx,1);keyF_total(k_idx,1)] ...
            [keyM_total(k_idx,2);keyF_total(k_idx,2)] ...
            [keyM_total(k_idx,3);keyF_total(k_idx,3)] ];
        
        rgb = [0 0 0];
        if lines(1,1) > lines(2,1)
            rgb(1) = .7;
        end
        if lines(1,2) > lines(2,2)
            rgb(2) = .7;
        end
        if lines(1,3) > lines(2,3)
            rgb(3) = .7;
        end
        plot3(lines(:,1),lines(:,2),lines(:,3),'color',rgb);
    end
    legend('Reference', 'Moving');
    keys_total = [keys_total size(keyF_total,1)];
    output_string = sprintf('Round%i: %i correspondences to calculate TPS warp',sequencing_round,size(keyF_total,1));
    title(output_string);
    disp(output_string)
    view(45,45);
    hold off;
    
    for idx = 1:length(save_types)
        save_type = save_types{idx};
        figfilename = fullfile(reportingDir,...
            sprintf('%s_featuresInRound%.03i.%s',...
            'registration',...
            sequencing_round,...
            save_type));
        saveas(gcf,figfilename,save_type)
    end
end
