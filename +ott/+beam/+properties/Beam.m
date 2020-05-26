classdef (Abstract) Beam < ott.utils.RotationPositionProp
% A base class for Beam and abstract.Beam representations.
% Inherits from :class:`ott.utils.RotationPositionProp`.
%
% Any units can be used for the properties as long as they are
% consistent in all specified properties.  Calculated quantities
% will have these units.
%
% This class defines the common properties and methods to these
% two classes.
%
% Properties
%   - position      -- Position of the beam or array
%   - rotation      -- Rotation of the beam or array
%
% Dependent properties
%   - vacuum        -- Vacuum material linked to the Medium
%   - wavelength    -- Wave-length of the beam in medium
%   - wavenumber    -- Wave-number of beam in medium
%   - wavelength0   -- Wave-length of the beam in vacuum
%   - wavenumber0   -- Wave-number of beam in vacuum
%
% Abstract properties
%   - power         -- The power of the beam (may be infinite)
%   - omega         -- Beam optical frequency
%   - medium        -- Medium where beam is propagating
%
% Methods
%  - rotate*     -- Beam rotation methods
%  - translate*  -- Beam translation methods

% Copyright 2020 Isaac Lenton
% This file is part of OTT, see LICENSE.md for information about
% using/distributing this file.

  properties (Abstract)
    omega            % Beam optical frequency
    medium           % Medium where beam is propagating
    power           % The power of the beam (may be infinite)
  end

  properties (Dependent)
    vacuum          % Vacuum material liked to the medium

    wavenumber      % Wave-number of beam in medium
    wavenumber0     % Wave-number of beam in vacuum
    wavelength      % Wavelength of beam
    wavelength0     % Vacuum wavelength of beam
  end

  methods (Static)
    function args = likeProperties(other, args)
      % Construct an array of like-properties
      %
      % Usage
      %   args = Beam.like(other, args)

      args = ott.utils.addDefaultParameter('position', other.position, args);
      args = ott.utils.addDefaultParameter('rotation', other.rotation, args);
      args = ott.utils.addDefaultParameter('omega', other.omega, args);
      args = ott.utils.addDefaultParameter('medium', other.medium, args);
    end
  end

  methods
    function beam = Beam(varargin)
      % Initialize beam properties
      %
      % Usage
      %   beam = beam@ott.beam.Properties(...)
      %
      % Named arguments
      %   - wavelength|wavelength0 (numeric) -- Beam wavelength
      %   - wavenumber|wavenumber0 (numeric) -- Beam wave-number
      %   - omega (numeric) -- Optical frequency of beam.
      %     Default: ``2*pi``
      %
      %   - vacuum (ott.beam.medium.Medium) -- Vacuum medium.
      %     Default: ``ott.beam.medium.Vacuum.Unitary``.
      %     If set, `medium` must not be Material.
      %
      %   - medium (ott.beam.medium.Medium|Material) -- Medium or
      %     material describing optical properties of medium.
      %     Default: ``ott.beam.medium.Vacuum.Unitary``.
      %
      %   - power (numeric) -- Initial beam power (if supported).
      %     No default, only sets property if argument passed.
      %
      % The medium is constructed from
      % :meth:`ott.beam.medium.Material.Simple`.  All unmatched parameters,
      % along with `vacuum` and `medium` are passed to this function.
      %
      % Only one of omega, wavelength or wave-number should be set.

      p = inputParser;
      p.KeepUnmatched = true;
      p.addParameter('omega', []);
      p.addParameter('wavelength', []);
      p.addParameter('wavelength0', []);
      p.addParameter('wavenumber', []);
      p.addParameter('wavenumber0', []);
      p.addParameter('vacuum', []);
      p.addParameter('medium', []);
      p.addParameter('position', []);
      p.addParameter('rotation', []);
      p.addParameter('power', []);
      p.parse(varargin{:});
      unmatched = ott.utils.unmatchedArgs(p);

      % Store power if supplied
      if ~any(strcmpi('power', p.UsingDefaults))
        beam.power = p.Results.power;
      end

      % Get default values from like
      % TODO: Use 'UsingDefaults' instead of isempty
      default_omega = 2*pi;
      default_vacuum = ott.beam.medium.Vacuum.Unitary();
      default_medium = default_vacuum;
      default_position = [0;0;0];
      default_rotation = eye(3);

      % Check number of omega related arguments
      % TODO: We often want to supply two of these (to specify medium)
      num_omega = isempty(p.Results.omega) ...
          + isempty(p.Results.wavelength) ...
          + isempty(p.Results.wavenumber) ...
          + isempty(p.Results.wavelength0) ...
          + isempty(p.Results.wavenumber0);
      assert(num_omega >= 4, ...
        'Must only provide one or two of omega|wavelength|wavenumber');

      % Get default values for medium construction
      medium = p.Results.medium;
      vacuum = p.Results.vacuum;
      if ~isempty(vacuum) && ~isempty(medium)
        assert(~isa(medium, 'ott.beam.medium.Material'), ...
            'medium must not be a material if vacuum is specified');
      elseif isempty(vacuum) && isempty(medium)
        medium = default_medium;
        vacuum = default_vacuum;
      elseif isempty(medium)
        medium = default_medium;
      elseif isempty(vacuum)
        if isa(medium, 'ott.beam.medium.Material')
          vacuum = medium.vacuum;
        else
          vacuum = default_vacuum;
        end
      end

      % Construct medium
      % TODO: Should we remove like from Materials too?
      beam.medium = ott.beam.medium.Material.Simple(...
          'vacuum', vacuum, 'like', medium, unmatched{:});
        
      % Store position/rotation
      if ~isempty(p.Results.position)
        beam.position = p.Results.position;
      else
        beam.position = default_position;
      end
      if ~isempty(p.Results.rotation)
        beam.rotation = p.Results.rotation;
      else
        beam.rotation = default_rotation;
      end

      % Calculate optical frequency
      if ~isempty(p.Results.omega)
        beam.omega = p.Results.omega;
      elseif ~isempty(p.Results.wavelength)
        beam = beam.setFrequency('wavelength', p.Results.wavelength);
      elseif ~isempty(p.Results.wavelength0)
        beam = beam.setFrequency('wavelength0', p.Results.wavelength0);
      elseif ~isempty(p.Results.wavenumber)
        beam = beam.setFrequency('wavenumber', p.Results.wavenumber);
      elseif ~isempty(p.Results.wavenumber0)
        beam = beam.setFrequency('wavenumber0', p.Results.wavenumber0);
      else
        beam.omega = default_omega;
      end
    end
    
    function beam = setWavelength(beam, val, mode)
      % Change the wavelength of the beam
      %
      % Usage
      %   beam = beam.setWavelength(val, mode)
      %
      % Parameters
      %   - mode (enum) -- Variable to change.  Either 'frequency' or
      %     'medium' to change the optical frequency or medium properties.
      
      switch mode
        case 'frequency'
          beam = beam.setFrequency('wavelength', val);
        case 'medium'
          beam.medium.speed = beam.omega ./ (2*pi) .* val;
        otherwise
          error('Unknown mode selection');
      end
      
      assert(nargout == 1, 'Expected one output argument');
    end
    
    function varargout = setWavenumber(beam, val, mode)
      % Change the wavelength of the beam
      %
      % Usage
      %   beam = beam.setWavenumber(val, mode)
      %
      % Parameters
      %   - mode (enum) -- Variable to change.  Either 'frequency' or
      %     'medium' to change the optical frequency or medium properties.
      
      [varargout{1:nargout}] = beam.setWavelength(2*pi./val, mode);
    end

    function beam = setFrequency(beam, name, val)
      % Set the optical frequency from another named parameter
      %
      % Usage
      %   beam = beam.setFrequency(name, value)
      %
      % Parameters
      %   - name (enum) -- One of the named properties supported by
      %     the constructor.
      %
      %   - value (numeric) -- Value to use in calculation

      switch name
        case 'wavelength'
          beam.omega = 2*pi*beam.medium.speed./val;
        case 'wavelength0'
          beam.omega = 2*pi*beam.vacuum.speed./val;
        case 'wavenumber'
          beam.omega = beam.medium.speed.*val;
        case 'wavenumber0'
          beam.omega = beam.vacuum.speed.*val;
        otherwise
          error('Unknown parameter name');
      end
      
      assert(nargout == 1, 'Expected one output argument');
    end

    function data = arrayApply(beam, func, varargin)
      % Apply function to each array in the beam array output.
      %
      % Usage
      %   data = beam.arrayApply(func, ...)
      %   Additional parameters are passed to the function.
      %
      % This function is overloaded by Array types in order to
      % implement incoherent combination.

      data = func(varargin{:});
    end
  end

  methods % Getters/setters
    function val = get.vacuum(beam)
      val = beam.medium.vacuum;
    end

    % Wavelength and wavenumber only have getters (setters are ambiguous)
    function val = get.wavelength(beam)
      val = 2*pi.*beam.medium.speed ./ beam.omega;
    end
    function val = get.wavenumber(beam)
      val = beam.omega ./ beam.medium.speed;
    end

    % Wavenumber is dependent on frequency
    function val = get.wavenumber0(beam)
      val = beam.omega ./ beam.vecuum.speed;
    end
    function beam = set.wavenumber0(beam, val)
      beam = beam.setFrequency('wavenumber0', val);
    end

    % Wavenumber is dependent on frequency
    function val = get.wavelength0(beam)
      val = 2*pi.*beam.vacuum.speed ./ beam.omega;
    end
    function beam = set.wavelength0(beam, val)
      beam = beam.setFrequency('wavelength0', val);
    end
  end
end
