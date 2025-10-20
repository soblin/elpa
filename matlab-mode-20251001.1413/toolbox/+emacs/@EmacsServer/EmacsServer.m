% Copyright (C) 2019-2024 Free Software Foundation, Inc.
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

classdef EmacsServer < handle
% Class EMACSSERVER - Support a TCP connection to an Emacs server.
% Collects input from Emacs, and runs commands.
% Sends commands to Emacs from MATLAB if needed.
%

    properties
        % True to send Emacs Stack info as the user steps through the debugger.
        FollowStack = false;
    end

    properties (Access='protected')
        tcpclient;
        timer;
    end

    methods
	function ES = EmacsServer()
	% Construct the Emacs Server.  Create the TCP client and

            ES.tcpclient = tcpclient('localhost', 32475);

            if isempty(ES.tcpclient)
                delete(ES);
                error('Unable to connect to Emacs.');
            end

            ES.timer = timer('Name','Emacs NetShell timer', ...
                             'TimerFcn', {@watch_emacs ES}, ...
                             'Period', 3,...
                             'BusyMode', 'drop',...
                             'ErrorFcn', {@drop_emacs ES},...
                             'ExecutionMode', 'fixedSpacing');

            start(ES.timer);

            ES.SendCommand('init');
        end

        function delete(ES)
            try
                stop(ES.timer);
            end

            delete(ES.tcpclient);
            delete(ES.timer);
        end

        function SendCommand(ES, cmd, data)
        % Commands have 2 parts, the COMMAND and DATA.
        % COMMAND is sent to emacs followed by a newline.  This should be a single
        % word.  SendCommand adds the newline.
        % DATA can be any string.
        % The full command is terminated by a NULL -> uint8(0)

            write(ES.tcpclient, uint8([ cmd newline]));

            if nargin > 2 && ~isempty(data)
                write(ES.tcpclient, uint8(data));
            end
            write(ES.tcpclient, uint8(0));
        end

        function SendEval(ES, lispform)
        % Send the LISPFFORM for Emacs to evaluate.

            ES.SendCommand('eval', lispform);
        end
    end

    properties (Access='protected')
        accumulator = '';
    end

    methods (Access='protected')
        function ReadCommand(ES)

            msg = char(read(ES.tcpclient));

            ES.accumulator = [ ES.accumulator msg ];

            while ~isempty(ES.accumulator)

                k = strfind(ES.accumulator, char(0));

                if isempty(k)
                    % No complete commands.  Exit.
                    disp(['partial accumulation: ' ES.accumulator]);
                    return;
                end

                datamsg = ES.accumulator(1:k(1)-1);
                ES.accumulator = ES.accumulator(k(1)+1:end);

                % Now peal the datamsg into it's constituent parts.
                cr = strfind(datamsg, newline);

                if isempty(cr)
                    cmd = datamsg;
                    data = '';
                else
                    cmd = datamsg(1:cr(1)-1);
                    data = datamsg(cr(1)+1:end);
                end

                ES.ExecuteRemoteCommand(cmd, data);
            end
        end

        function ExecuteRemoteCommand(ES, cmd, data)
        % When we receive a command from Emacs, eval it.

            switch cmd

              case 'nowledge'
                disp('Acknowledgement received.');

              case 'ack'
                disp('Ack Received.  Sending ack back.');
                ES.SendCommand('nowledge');

              case 'eval'
                try
                    disp(['>> ' data]);
                    evalin('base',data);
                catch ERR
                    disp(ERR.message);
                    ES.SendCommand('error', ERR.message);
                end

              case 'evalc'
                disp('Evalc request.');
                try
                    OUT = evalc(data);
                catch ERR
                    OUT = ERR.message;
                end
                if ~isempty(OUT)
                    ES.SendCommand('output',uint8(OUT));
                else
                    disp('No output');
                end

              otherwise
                disp('Unknown command from Emacs');
            end
        end

    end
end

function watch_emacs(~, ~, ES)
% Timer Callback Function:
% Watch for bytes available from the Emacs network connection, and act on any events.

    ba = ES.tcpclient.BytesAvailable;

    if ba > 0

        ES.ReadCommand();

    else
        % Nothing received
        %disp('No Luv from Emacs');

        % Check if we are still alive.  We can only do that with a
        % write- so send an empty message.
        try
            write(ES.tcpclient, 0);
        catch
            disp('Connection to Emacs lost.  Shutting down net server');
            delete(ES);
        end
    end

    if ES.FollowStack
        es = getappdata(groot, 'EmacsStack');
        [ST, I] = dbstack('-completenames');
        es.updateEmacs(ST, I);
    end

end

function drop_emacs(~, ~, ES)
% If the timer throws an error, then shutdown.

    delete(ES);

    disp('Error in timer, dropping connection to Emacs.');

end

% LocalWords:  Ludlam LISPFFORM datamsg nowledge Luv completenames
