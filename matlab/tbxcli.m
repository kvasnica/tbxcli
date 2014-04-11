function tbxcli(varargin)
% TBXCLI: command-line interface for tbxmanager.com
%
% Basic syntax:
%   tbxcli version create
%   tbxcli version delete
%   tbxcli link create
%   tbxcli link delete
%   tbxcli prepare
%   tbxcli upload
%
% You will be prompted to enter additional required information via
% keyboard, such as the package name, version ID, etc. You can store
% default values for missing data via "tbxcli setup" (see below).
%
% Advanced syntax:
%   tbxcli --package=mpt --version=1.0 --repository=stable version create
%   tbxcli --package=mpt --version=1.0 --platform=all --url=URL link create
%   tbxcli --package=mpt --version=1.0 version delete
%   tbxcli --package=mpt --version=1.0 --platform=maci link delete
%
% Ordering of options is arbitrary.
%
% Set and store default options:
%   tbxcli setup
%
% Show stored default options:
%   tbxcli setup show
%
% Delete stored defaults:
%   tbxcli setup delete
%
% Global options (can be saved via "tbxcli setup")
%   --login=LOGIN       your tbxmanager.com login (=email)
%   --password=PASSWORD your tbxmanager.com password
%   --package=PKG       default package name
%   --platform=PLT      default platform (use 'all' for all platforms)
%   --repository=REPO   default repository ('stable' or 'unstable')

% Copyright is with the following author(s):
%
% (c) 2013 Michal Kvasnica, Slovak University of Technology in Bratislava
%          michal.kvasnica@stuba.sk

% ------------------------------------------------------------------------
% Legal note:
%   This program is free software; you can redistribute it and/or
%   modify it under the terms of the GNU General Public
%   License as published by the Free Software Foundation; either
%   version 2.1 of the License, or (at your option) any later version.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%   General Public License for more details.
%
%   You should have received a copy of the GNU General Public
%   License along with this library; if not, write to the
%     Free Software Foundation, Inc.,
%     59 Temple Place, Suite 330,
%     Boston, MA  02111-1307  USA
% ------------------------------------------------------------------------

%% check dependencies
if ~usejava('jvm')
	error('TBXCLI:NOJAVA', 'TBXCLI requires the Java virtual machine.');
elseif ~exist('containers.Map', 'class')
	error('TBXCLI:OLDMATLAB', 'TBXCLI requires Matlab R2011a or newer');
end

%% find indices of options in varargin (options start with '-')
is_option = cellfun(@(v) startswith(v, '-'), varargin);

%% parse options
Options = containers.Map;
for i = find(is_option)
	parsed = parse_option(varargin{i});
	if parsed.valid
		Options(parsed.option) = parsed.value;
	else
		fprintf('Ignoring invalid option "%s"\n', varargin{i});
	end
end

%% keep only commands, preserve their ordering
Commands = varargin(~is_option);
% at least one command must remain
if isempty(Commands)
	error('TBXCLI:BADCOMMAND', 'At least one command please.');
end

%% dispatch commands
% expand command name, e.g. "ve" -> "version"
supported_commands = {'version', ...
	'link', ...
	'setup', ...
    'prepare', ...
    'upload', ...
	'help'};
try
	command = tbx_expandChoice(lower(Commands{1}), supported_commands);
catch err
	error(err.message);
end

switch lower(command)
	case 'version',
		cmd_fun = @tbxcli_version;
	case 'link',
		cmd_fun = @tbxcli_link;
	case 'setup',
		cmd_fun = @tbxcli_setup;
    case 'prepare',
        cmd_fun = @tbxcli_prepare;
    case 'upload',
        cmd_fun = @tbxcli_upload;
	case 'help',
		help(mfilename);
		return
end

try
	feval(cmd_fun, Options, Commands{:});
catch err
	if ~isempty(err.identifier) && isempty(strfind(err.identifier, 'TBXCLI'))
		% unexpected error
		rethrow(err);
	else
		% expected error
		fprintf('\n%s\n\n', err.message);
		error('TBXCLI:ERROR', 'Cannot continue, see message above.');
	end
end


end

%%
function tbxcli_prepare(Options, varargin)
% Create a new archive from a given directory:
%   tbxcli --package=mpt --version=1.0 --dir=mydir --format=zip --platform=all prepare
%
% By default, --format=zip

RequiredOptions = {'package', 'version', 'platform', 'dir'};
Optional = { {'format', 'zip'} };

% ask for values of missing options
Options = tbxcli_askOptions(Options, RequiredOptions, Optional);

% construct the filename
ArchiveName = tbxcli_archive_name(Options);

% ask when rewriting
fid = fopen(ArchiveName, 'r');
if fid~=-1
    % file exists
    fclose(fid);
    fprintf('\nWARNING: file "%s" already exists!\n\n', ArchiveName);
    answer = input('Overwrite? [y/n]: ', 's');
    if lower(answer)~='y'
        % abort
        return
    end
end

% create the archive
switch Options('format')
    case 'zip'
        zip(ArchiveName, Options('dir'));
        
    otherwise
        error('TBXCLI:UnknownInput', 'Format "%s" is not supported.', Options('format'));
end

fprintf('\nCreated archive: %s\n', ArchiveName);

end

%%
function tbxcli_upload(Options, varargin)
% Upload a given archive to a given URL
%   tbxcli --package=mpt --version=1.0 --dest=ssh://server upload METHOD
%
% Supported methods:
%   * 'scp'

if length(varargin)<2
	error('TBXCLI:BADCOMMAND', 'At least two commands please');
end
UploadMethod = varargin{2};
RequiredOptions = {'package', 'version', 'platform', 'dest'};
Optional = { {'format', 'zip'} };

% ask for values of missing options
Options = tbxcli_askOptions(Options, RequiredOptions, Optional);

% construct the filename
archive = tbxcli_archive_name(Options);

% does the file exist?
fid = fopen(archive, 'r');
if fid<0
    error('TBXCLI:FileNotFound', 'File "%s" not found in the current directory.', archive);
end
fclose(fid);

% upload using selected method
switch lower(UploadMethod)
    case 'scp'
        cmd = sprintf('scp %s %s', archive, Options('dest'));
        fprintf('\nExecuting "%s"\n', cmd);
        system(cmd);
        
    otherwise
        error('TBXCLI:UnknownInput', 'Upload method "%s" is not supported.', Options('format'));
end

fprintf('\nFile "%s" uploaded to "%s".\n', archive, Options('dest'));

end


%%
function name = tbxcli_archive_name(Options)
% Constructs the archive name based on PACKAGE, VERSION, and PLATFORM

    function in = safestr(in)
        unsafe = ' !@#$%^&*()-+={}[]\;'':"<>,.?/';
        for i = 1:length(unsafe)
            in = strrep(in, unsafe(i), '_');
        end
    end

name = sprintf('%s_%s_%s.%s', safestr(Options('package')), ...
    safestr(Options('version')), ...
    safestr(Options('platform')), ...
    Options('format'));
end

%%
function tbxcli_setup(Options, varargin)
% Set all default options:
%   tbxcli setup
%
% Show default options:
%   tbxcli setup show
%
% Set selected default options:
%   tbxcli setup set login password package ...
%
% Delete selected default options:
%   tbxcli setup delete login password package ...
%
% Delete all default options:
%   tbxcli setup delete *

if length(varargin)==1
	% tbxcli setup
	cmd_fun = @tbxcli_setup_new;
else
	supported_subcommands = {'show', 'delete' };
	subcommand = tbx_expandChoice(lower(varargin{2}), supported_subcommands);
	switch subcommand
		case 'show'
			cmd_fun = @tbxcli_setup_show;
		case 'delete'
			rmpref('TBXCLI');
			return
	end
end
feval(cmd_fun, Options, varargin{:});

end

%%
function tbxcli_setup_new(varargin)
% Set all default options:
%   tbxcli setup

fprintf('Set default options (leave a field empty for no default value)\n');
OptionsToSet = { 'login', 'password', 'package', 'repository', 'platform' };
Defaults = [];
for opt = OptionsToSet
	optname = opt{1};
	Defaults.(optname) = input(sprintf('%s: ', capitalize(optname)), 's');
end
setpref('TBXCLI', 'Defaults', Defaults);

end

%%
function tbxcli_setup_show(varargin)
% Show default options:
%   tbxcli setup show

if ~ispref('TBXCLI', 'Defaults')
	error('TBXCLI:BADCOMMAND', 'No saved options found.');
end
Defaults = getpref('TBXCLI', 'Defaults');
f = fields(Defaults);
for i = 1:length(f)
	fname = f{i};
	value = Defaults.(fname);
	fprintf('%s: %s\n', capitalize(fname), value);
end

end

%%
function value = tbxcli_setup_get(Option)
% returns value of the default option or '' if no default value exists

if ~ispref('TBXCLI', 'Defaults')
	value = '';
else
	Defaults = getpref('TBXCLI', 'Defaults');
	if ~isfield(Defaults, Option)
		value = '';
	else
		value = Defaults.(Option);
	end
end

end


%%
function tbxcli_link(Options, varargin)
% Create download link for "all" platforms for version "1.0" of package
% "mpt", pointing to a given URL:
%   tbxcli --package=mpt --version=1.0 --platform=all --url=URL link create
%
% Delete download link for platform MACI for version "1.0" of package "mpt":
%   tbxcli --package=mpt --version=1.0 --platform=maci link delete

if length(varargin)<2
	error('TBXCLI:BADCOMMAND', 'At least two commands please');
end

supported_subcommands = {'create', 'delete'};
subcommand = tbx_expandChoice(lower(varargin{2}), supported_subcommands);
switch subcommand
	case 'create',
		URL = 'links/create';
		RequiredOptions = {'package', 'version', 'platform', 'url'};
	case 'delete',
		URL = 'links/delete';
		RequiredOptions = {'package', 'version', 'platform'};
end
tbxcli_rest(URL, Options, RequiredOptions);

end

%%
function tbxcli_version(Options, varargin)
% Create version "1.0" in the "stable" repository of package "mpt":
%   tbxcli --package=mpt --repository=stable --version=1.0 version create
%
% Delete version "1.0" of package "mpt":
%   tbxcli --package=mpt --version=1.0 version delete

if length(varargin)<2
	error('TBXCLI:BADCOMMAND', 'At least two commands please');
end

supported_subcommands = {'create', 'delete'};
subcommand = tbx_expandChoice(lower(varargin{2}), supported_subcommands);
switch subcommand
	case 'create',
		URL = 'versions/create';
		RequiredOptions = {'package', 'repository', 'version'};
	case 'delete',
		URL = 'versions/delete';
		RequiredOptions = {'package', 'version'};
end
tbxcli_rest(URL, Options, RequiredOptions);

end

%%
function tbxcli_rest(Command, Options, RequiredOptions)
% queries the tbxmanager.com rest api

Server = 'http://www.tbxmanager.com/api/v1/';

% login and password are always required
RequiredOptions = fliplr(RequiredOptions);
RequiredOptions{end+1} = 'password';
RequiredOptions{end+1} = 'login';
RequiredOptions = fliplr(RequiredOptions);

% ask for values of missing options
Options = tbxcli_askOptions(Options, RequiredOptions);

% convert options into key=value pairs
DoNotInclude = {'login', 'password'};
OptionsUrl = tbxcli_options2url(Options, DoNotInclude);

% assemble the full REST URL
URL = [Server, Command, '?', OptionsUrl];

fprintf('\nContacting %s\n', URL);

info = urlread_auth(URL, Options('login'), Options('password'));
fprintf('%s (%d): %s\n', info.response, info.status, info.msg);

end

%%
function url = tbxcli_options2url(Options, DoNotInclude)
% generates opt1=val1&opt2=val2&...
%
% excludes options listed in DoNotInclude

url = '';
for opt = Options.keys
	if ~ismember(opt{1}, DoNotInclude)
		url = [url, '&', opt{1}, '=', Options(opt{1})];
	end
end
% remove the leading '&'
url = url(2:end);

end


%%
function info = urlread_auth(URL, User, Password)
% urlread() with basdic authorization

encoded_auth = ['Basic ', base64encode([User ':' Password]), '=='];
jURL = java.net.URL(URL);
conn = jURL.openConnection();
conn.setRequestProperty('Authorization', encoded_auth);
conn.connect();
info = struct('success', false, 'msg', '', 'response', '', 'status', 400);

try
	info.status = conn.getResponseCode();
	info.response = char(conn.getResponseMessage());
	info.msg = char(readstream(conn.getInputStream()));
	info.success = true;
catch
	info.msg = char(readstream(conn.getInputStream()));
	%info.response = char(readstream(conn.getErrorStream()));
	info.response = 'Error';
end

end

%%
function out = readstream(inStream)
%READSTREAM Read all bytes from stream to uint8

try
    import com.mathworks.mlwidgets.io.InterruptibleStreamCopier;
    byteStream = java.io.ByteArrayOutputStream();
    isc = InterruptibleStreamCopier.getInterruptibleStreamCopier();
    isc.copyStream(inStream, byteStream);
    inStream.close();
    byteStream.close();
    out = typecast(byteStream.toByteArray', 'uint8');
catch err
    out = [];
end

end

%%
function out = base64encode(in)
% Java-based base64 encoder

encoder = sun.misc.BASE64Encoder();
out = char(encoder.encode(java.lang.String(in).getBytes()));

end

%%
function Options = tbxcli_askOptions(Options, Required, Optional)
% asks for values of missing required options

DoNotShow = { 'login', 'password' };

% set missing options to defaults
for f = Required
	fname = f{1};
	if ~Options.isKey(fname)
		value = tbxcli_setup_get(fname);
		if ~isempty(value)
			Options(fname) = value;
		end
	end
end

% display pre-set Options
for f = setdiff(Required, DoNotShow)
	fname = f{1};
	if Options.isKey(fname)
		fprintf('%s: %s\n', capitalize(fname), Options(fname));
	end
end

% ask for remaining Options
for f = Required
	fname = f{1};
	if ~Options.isKey(fname)
		Options(fname) = input(sprintf('%s: ', capitalize(fname)), 's');
	end
end

% fill in optional settings
if nargin==3
    for i=1:length(Optional)
        key = Optional{i}{1};
        value = Optional{i}{2};
        if ~Options.isKey(key)
            Options(key) = value;
        end
    end
end

end

%%
function cap = capitalize(str)
% capitalizes a given string

cap = str;
cap(1) = upper(str(1));
% pad with spaces
cap = [repmat(' ', 1, max(0, 10-length(cap))), cap];

end

%%
function parsed = parse_option(option)
% parses a single option
%
% Input: '--property=value'
% Output: structure with following fields:
%  .option: 'property'
%   .value: 'value'
%   .valid: true if the option was parsed correctly, false otherwise

parsed = struct('option', '', 'value', '', 'valid', false);

% valid option must:
%  * be a string
%  * start with '--'
%  * contain exactly one "="
%  * have a non-empty value
eq_pos = find(option=='=');
if isa(option, 'char') && startswith(option, '--') && ...
		length(eq_pos)==1 && length(option)>eq_pos
	parsed.option = option(3:eq_pos-1);
	parsed.value = option(eq_pos+1:end);
	parsed.valid = true;
end

end

%%
function flag = startswith(string, prefix)
% returns true if STRING starts with PREFIX

flag = length(string)>=length(prefix) && isequal(string(1:length(prefix)), prefix);

end

%%
function answer = tbx_expandChoice(cmd, choices)
% returns element of cell array "choices" that start with the string "cmd"

candidates = {};
if ~iscell(choices)
	choices = { choices };
end
for i = 1:length(choices)
	if length(choices{i}) >= length(cmd)
		if isequal(choices{i}(1:length(cmd)), cmd)
			candidates{end+1} = choices{i};
		end
	end
end

if isempty(candidates)
	error('TBXCLI:BADCOMMAND', 'Unrecognized command/option "%s".', cmd);
	
elseif length(candidates)==1
	% unambiguous choice
	answer = candidates{1};
	
else
	fprintf('\nThe choice "%s" is ambiguous. Possible matches are:\n', cmd);
	for i = 1:length(candidates)
		fprintf('\t%s\n', candidates{i});
	end
	fprintf('\n');
	error('TBXCLI:BADCOMMAND', ...
		'Ambiguous choice, please refine your input.');
end

end
