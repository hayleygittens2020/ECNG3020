[files,path] = uigetfile('*.nmf',  'Select NMF','MultiSelect','on'); %selecting multiple nmf files
if iscell(files) == 0  %checks if the files variable is a cell, if not a cell it turns the variable into a cell
    files = {files};
end

exportfileID = fopen('gps_mimo_drate_ci_export.csv','wt');%https://www.mathworks.com/matlabcentral/answers/110573-write-string-in-text-file
for a=1:length(files)
    filename = files{a};
    importfileID = fopen([path filename]);
    numLines = linesInFile(importfileID);

    %% Extracting all the lines that contain tags in check cell array
    check = {'GPS,','MIMOMEAS,','CI,', 'DRATE,'};
    
    readNMFWaitBar = waitbar(0, 'Starting','Name',['NMF Extracted Tags - ', strjoin(check,'|')]);%https://www.mathworks.com/matlabcentral/answers/599287-progress-bar-and-for-loop
    tic
    for b= 1:numLines
        tline = fgetl(importfileID);%https://www.mathworks.com/matlabcentral/answers/22289-read-an-input-file-process-it-line-by-line
        if ~isempty(regexp(tline,strjoin(check,'|'), 'once'))%https://www.mathworks.com/matlabcentral/answers/304142-searching-multiple-strings-at-one-time
            fprintf(exportfileID, [tline,'\n']);
        end
     waitbar(b/numLines, readNMFWaitBar, sprintf('Data Extraction Progress: %d %%', floor((b/numLines)*100)));
    end

    toc
    close(readNMFWaitBar);
end
fclose(importfileID);
fclose(exportfileID);
clearvars -except check    


%% Importing extracted data into MATLAB struct
    extractedfileID = fopen('gps_mimo_drate_ci_export.csv', 'rb');
    measurments.data = cell(1,4);
    NumGPSCoordinates = 0;
    NumMIMOMEAS = 0;
    NumDRATE = 0;
    NumCI = 0;
    extractedNumLines = linesInFile(extractedfileID);
    extractedDataMATLABImport= waitbar(0, 'Starting','Name',['File Imported Tags - ', strjoin(check,'|')]);
    for i= 1:extractedNumLines
        tline = fgetl(extractedfileID);
        if tline ~= -1
            if ~isempty(regexp(tline,'GPS', 'once'))
                NumGPSCoordinates = NumGPSCoordinates +1;
                measurments.data{NumGPSCoordinates,1} = tline;
                measurments.data{NumGPSCoordinates,2} = '';
                measurments.data{NumGPSCoordinates,3} = '';
                measurments.data{NumGPSCoordinates,4} = '';
                NumMIMOMEAS = 0;
                NumDRATE = 0;
                NumCI = 0;
            end
            if ~isempty(regexp(tline,'MIMOMEAS', 'once'))
                NumMIMOMEAS = NumMIMOMEAS +1;
                measurments.data{NumGPSCoordinates,2}{NumMIMOMEAS,1} = tline;
            end
            if ~isempty(regexp(tline,'DRATE', 'once'))
                NumDRATE = NumDRATE +1;
                measurments.data{NumGPSCoordinates,3}{NumDRATE,1} = tline;
            end
             if ~isempty(regexp(tline,'CI', 'once'))
                NumCI = NumCI +1;
                measurments.data{NumGPSCoordinates,4}{NumCI,1} = tline;
            end
        end
        waitbar(i/extractedNumLines, extractedDataMATLABImport, sprintf('MATLAB Import Progress: %d %%', floor((i/extractedNumLines)*100)));
    end
    [measurments.NumGPSData, ~] = size(measurments.data);
    close(extractedDataMATLABImport)
    fclose(extractedfileID);
    clearvars -except measurments 

%% Clean Data Function
data = cell(1,4);
empty = 0;
GPSerror = 0;
RSRPerror = 0;
DataRateError = 0;
CarrierError = 0;

for x = 1:measurments.NumGPSData
    % GPS Data
    GPSline = measurments.data{x,1};
    splitGPSline = strsplit(GPSline, ',');
    if length(splitGPSline) < 9
        continue
    else
        if str2double(splitGPSline{1,4}) < 9.9 || str2double(splitGPSline{1,4}) > 12  
            GPSerror = GPSerror + 1;
            continue
        else
            %dtv = datetime(splitGPSline{1,2},'InputFormat','HH:mm:ss.SSS', 'Format','HH:mm:ss.SSS');
            %time = timeofday(dtv);
            %data{x,1} = time; 
            %splitTime = strsplit(string(splitGPSline{1,2}),':');
            %data{x,1} = str2double(splitTime(1,1)+ splitTime(1,2)+splitTime(1,3));
            data{x,1} = splitGPSline{1,2}; %Time
            data{x,2} = str2double(splitGPSline{1,4}); %Latitude 
            data{x,3} = str2double(splitGPSline{1,3}); %Longitude
            data{x,4} = str2double(splitGPSline{1,9}); %Velocity
        end
    end
   % MIMO Data
       Mline = measurments.data{x,2};  %Checks if there is a measurement value in the second column
    if isempty(Mline)
        empty = empty+1;    %empty MIMO lines
        continue
    else
            MIMOline = Mline{1,1};
            splitMIMOline = strsplit(MIMOline, ',');              
            lengMIMO = length(splitMIMOline);
            if lengMIMO < 14 || str2double(splitMIMOline{1,14}) > 1
                RSRPerror = RSRPerror + 1;
                continue
            else     
                data{x,5} = str2double(splitMIMOline{1,9}); %PCI
                data{x,6} = str2double(splitMIMOline{1,7}); %Band
                data{x,7} = str2double(splitMIMOline{1,8}); %EARFCN
                data{x,8} = str2double(splitMIMOline{1,14}); %RSRP
                data{x,9} = str2double(splitMIMOline{1,12}); %RSSI
                data{x,10} = str2double(splitMIMOline{1,13}); %RSRQ
            end
    end 
     % CI Data
    Cline = measurments.data{x,4}; 
    if isempty(Cline)
        empty = empty+1;
        continue
    else
            Carrierline = Cline{1,1};
            splitCarrierline = strsplit(Carrierline, ',');              
            lengCarrier = length(splitCarrierline);
            if lengCarrier < 7 || str2double(splitCarrierline{1,7}) < 1
                CarrierError = CarrierError + 1;
                continue
            else   
                data{x,11} = str2double(splitCarrierline{1,5}); %RSSNR
            end  
    end       
    % DRATE Data
    Dline = measurments.data{x,3}; 
    if isempty(Dline)
        empty = empty+1;
        continue
    else
            DRATEline = Dline{1,1};
            splitDRATEline = strsplit(DRATEline, ',');              
            lengDRATE = length(splitDRATEline);
            if lengDRATE < 7 || str2double(splitDRATEline{1,7}) < 1
                DataRateError = DataRateError + 1;
                continue
            else  
                %Throughput - from B to MB

                data{x,12} = str2double(splitDRATEline{1,6}); 
                data{x,13} = str2double(splitDRATEline{1,7}); %Bytes Transferred
            end
    end  
end

for col = 1:width(data)
    for x = 1:measurments.NumGPSData
        if data{x,col} ~= 0
            continue 
        else
            for y = 1:width(data)
                data{x,y} = [];
            end
        end
    end
end
clean = data(~all(cellfun(@isempty,data),2),:);
colNames = {'Time', 'Latitude', 'Longitude', 'Velocity', 'PCI','Frequency Band', 'EARFCN','RSRP','RSSI','RSRQ','RSSNR', 'Throughput','Bytes Transferred'};
cleantable= cell2table(clean,"VariableNames",colNames);
cleanData = sortrows(cleantable,'Time');

writetable(cleanData,'NemoDriveTest.xlsx', 'Sheet',1)
clearvars -except measurments 

%% Clusters 
Test = NemoDriveTest;
%% Zone1 - UWI
Zone1 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone1 = Test{x,2};
    longZone1 = Test{x,3}; 
    if ((latZone1 >=  10.63701 && latZone1 <=   10.646789) && (longZone1 >= -61.4052  && longZone1 <= -61.396876))
        for y = 1: width(Test) 
            Zone1(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 1'
hold on 

for x = 1:length(Zone1)
    g = geoplot(Zone1(x,2),Zone1(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end

%% Zone2 - Roadways

Zone2 = zeros();
s = 1;

for x = 1:size(Test,1)
    latRoad = Test{x,2};
    longRoad = Test{x,3};  
    if ((latRoad >=  10.645115 && latRoad <= 10.652963) && (longRoad >= -61.407567 && longRoad <= -61.394299))
        for y = 1: width(Test) 
            Zone2(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 2'
hold on

for x = 1:length(Zone2)
    h = geoplot(Zone2(x,2),Zone2(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end


%% Zone3 - Santa Magarita
Zone3 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone3 = Test{x,2}; 
    longZone3 = Test{x,3}; 
    if ((latZone3 >= 10.652400 && latZone3 <= 10.658521) && (longZone3 >= -61.405294  && longZone3 <= -61.399023))
        for y = 1: width(Test) 
            Zone3(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 3'
hold on

for x = 1:length(Zone3)
    h = geoplot(Zone3(x,2),Zone3(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end



%% Zone4 - Mount St. Benedict
Zone4 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone4 = Test{x,2};  
    longZone4 = Test{x,3}; 
    if ((latZone4 >=  10.651879 && latZone4<=  10.6632) && (longZone4 >= -61.397082  && longZone4 <= -61.391774))
        for y = 1: width(Test) 
            Zone4(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 4'
hold on 

for x = 1:length(Zone4)
    g = geoplot(Zone4(x,2),Zone4(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end

clearvars -except Test Zone1 Zone2 Zone3 Zone4
