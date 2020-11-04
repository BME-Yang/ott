classdef Bsc < matlab.mixin.Heterogeneous ...
    & ott.utils.RotateHelper & ott.utils.TranslateHelper
% Class representing vector spherical wave function beam shape coefficients.
% Inherits from :class:`ott.utils.RotateHelper`
% and :class:`ott.utils.TranslateHelper`.
%
% Unlike the previous version of the toolbox, the `Bsc` class does not track
% the position/rotation of the beam.  This is to avoid suggesting that the
% beam actually has a well defined position/rotation.
% Other notable differences include the use of Hetrogeneous arrays,
% support for arbitrary beam data data-types, and moving user friendly
% features such as nice units to :class:`ott.beam.Beam`.
%
% `Bsc` rotations have units of radians and displacements have units of
% medium wavelength.
%
% Properties
%   - a         -- Beam shape coefficients `a` vector
%   - b         -- Beam shape coefficients `b` vector
%   - Nmax      -- (Dependent) Truncation number for VSWF coefficients
%   - power     -- (Dependent) Power of the beam shape coefficients
%
% Static methods
%   - FromDenseBeamVectors -- Construct beam from dense beam vectors.
%   - BasisSet             -- Generate basis set of VSWF beams
%
% Methods
%   - Bsc        -- Class constructor
%   - issparse   -- Check if the beam data is sparse
%   - full       -- Make the beam data full
%   - sparse     -- Make the beam data sparse
%   - makeSparse -- Make the beam data sparse (with additional options)
%   - setNmax    -- Resize beam data to desired Nmax
%   - shrinkNmax -- Reduce Nmax while preserving beam power
%   - gpuArray   -- Make beam a gpuArray
%   - gather     -- Apply gather to beam data
%   - rotate*    -- (Inherited) Functions for rotating the beam
%   - translate* -- (Inherited) Functions for translating the beam
%   - translateZ -- Translation along the theta=0 (z) axis
%   - getCoefficients -- Get a/b vectors with additional options
%   - setCoefficients -- Set a/b vectors with additional options
%
% Mathematical operations
%   - sum       -- Combine array of beams using summation
%   - times     -- Scalar multiplication of beam vectors
%   - mtimes    -- Scalar and matrix multiplication of beam vectors
%   - rdivide   -- Scalar division of beam vectors
%   - mrdivide  -- Scalar division of beam vectors
%   - uminus    -- Negation of beam vectors
%   - minus     -- Subtraction of beam vectors
%   - plus      -- Addition of beam vectors
%   - real      -- Extract real part of BSC data
%   - imag      -- Extract imag part of BSC data
%   - abs       -- Calculate absolute value of BSC data
%
% Field calculation methods
%   - efieldRtp  -- Calculate electric field around the origin
%   - hfieldRtp  -- Calculate magnetic field around the origin
%   - efarfield  -- Calculate electric fields in the far-field
%
% Force and torque related methods
%   - force           -- Calculate the change in momentum between two beams
%   - torque          -- Calculate change in angular momentum between beams
%   - spin            -- Calculate change in spin momentum between beams
%
% Casts
%   - ott.bsc.Bsc     -- Downcast BSC superclass to base class
%   - ott.tmatrix.Tmatrix -- Create T-matrix from beam array

% This file is part of OTT, see LICENSE.md for information about
% using/distributing this file.

  properties
    a          % Beam shape coefficients `a` vector
    b          % Beam shape coefficients `b` vector
  end

  properties (Dependent)
    Nmax       % Truncation number for VSWF coefficients
    power      % Power of the beam shape coefficients
  end

  methods (Static)
    function bsc = FromDenseBeamVectors(a, b, n, m)
      % Construct a new Bsc instance from dense beam vectors.
      %
      % Usage
      %   bsc = Bsc.FromDenseBeamVectors(a, b, n, m)
      %
      % Parameters
      %   - a,b (numeric) -- Dense beam vectors.  Can be Nx1 or NxM for
      %     M beams.  Each row corresponds to n/m indices.
      %
      %   - n,m (numeric) -- Mode indices for beam shape coefficients.
      %     Must have same number of rows as a/b.

      % Check inputs
      assert(all(size(a) == size(b)), 'size of a must match size of b');
      assert(numel(n) == numel(m), 'length of m and n must match');
      assert(numel(n) == size(a, 1), 'length of n must match rows of a');

      % Generate combine indices
      ci = ott.utils.combined_index(n, m);

      % Calculate total_order and number of beams
      nbeams = size(a, 2);
      Nmax = max(n);
      total_orders = ott.utils.combined_index(Nmax, Nmax);

      % Replicate ci for 2-D beam vectors (multiple beams)
      [ci, cinbeams] = ndgrid(ci, 1:nbeams);

      if ~isempty(ci)
        fa = sparse(ci, cinbeams, a, total_orders, nbeams);
        fb = sparse(ci, cinbeams, b, total_orders, nbeams);
      else
        fa = sparse(0, 0);
        fb = sparse(0, 0);
      end

      bsc = ott.bsc.Bsc(fa, fb);
    end

    function varargout = BasisSet(ci)
      % Generate basis set of VSWF beams
      %
      % Usage
      %   beams = ott.bsc.Bsc.BasisSet(ci)
      %   Returns an array of ``2*numel(ci)`` beams for basis set.
      %
      %   [TE, TM] = ott.bsc.Bsc.BasisSet(ci)
      %   Returns two arrays for ``a`` modes and ``b`` modes.

      assert(isvector(ci) && isnumeric(ci) && all(ci > 0), ...
          'ci must be positive numeric vector');

      % Mode indices
      Z = sparse(max(ci), numel(ci));
      I = sparse(ci, 1:numel(ci), ones(size(ci)), max(ci), numel(ci));

      % Generate beams
      TE = ott.bsc.Bsc(I, Z);
      TM = ott.bsc.Bsc(Z, I);

      % Package output
      if nargout == 1
        varargout{1} = [TE, TM];
      else
        varargout{1} = TE;
        varargout{2} = TM;
      end
    end
  end

  methods
    function beam = Bsc(varargin)
      % Construct a new beam object
      %
      % Usage
      %   beam = Bsc() Constructs an empty Bsc beam.
      %
      %   beam = Bsc(a, b) constructs beam from a/b coefficients.
      %
      %   beam = Bsc(bsc) construct by copying existing beam coefficients.
      %
      % Parameters
      %   - a,b (numeric) -- Vectors of VSWF coefficients

      p = inputParser;
      p.addOptional('a', zeros(0, 1), ...
          @(x) isnumeric(x) || isa(x, 'ott.bsc.Bsc'));
      p.addOptional('b', zeros(0, 1), @isnumeric);
      p.parse(varargin{:});
      
      oa = p.Results.a;
      ob = p.Results.b;
      
      if nargin == 1 && isa(oa, 'ott.bsc.Bsc')
        [oa, ob] = oa.getCoefficients();
      end

      if ~ismatrix(oa) || size(oa, 2) > 1 ...
          || ~ismatrix(ob) || size(ob, 2) > 1
        % Construct array of beams
        sza = size(oa);
        szb = size(ob);
        assert(numel(sza) == numel(szb) && all(sza == szb), ...
          'dimensions of ''a'' and ''b'' must match');
        beam = repmat(beam, 1, sza(2:end));
        for ii = 1:numel(beam)
          beam(ii).a = oa(:, ii);
          beam(ii).b = ob(:, ii);
        end
      else
        % Construct single beam
        beam.a = oa;
        beam.b = ob;
      end
    end

    function tmatrix = ott.tmatrix.Tmatrix(beam)
      % Create T-matrix from beam array
      %
      % Usage
      %   tmatrix = ott.tmatrix.Tmatrix(beam)
      %
      % Each beam in the beam array becomes a column of the T-matrix.
      % Uses :meth:`getCoefficients` to get the T-matrix data.

      data = beam.getCoefficients();
      tmatrix = ott.tmatrix.Tmatrix(data);
    end

    %
    % Field calculation functions
    %

    function [E, data] = efarfield(beam, rtp, varargin)
      % Calculate E far-field
      %
      % Usage
      %   [E, data] = beam.efarfield(rtp, ...)
      %
      % Parameters
      %   - rtp (3xN | 2xN numeric) -- Spherical coordinates for field
      %     calculation. Packaged [r; theta; phi] or [theta; phi].
      %
      % Optional named parameters
      %   - data (ott.utils.VswfData) -- Field data for repeated field
      %     calculation.  Default is an empty VswfData structure.
      %
      %   - basis (enum) -- Basis for field calculation.  Must be either
      %     'incoming' or 'outgoing'.  Default: ``'incoming'``.

      p = inputParser;
      p.addParameter('data', ott.utils.VswfData(), ...
          @(x) isa(x, 'ott.utils.VswfData'));
      p.addParameter('basis', 'incoming');
      p.parse(varargin{:});

      % Ensure rtp size is 3xN
      [~, rtp] = ott.utils.rtpFarfield(rtp);

      ci = beam.getCombinedIndex();
      [n, ~] = ott.utils.combined_index(ci);
      Nn = 1./sqrt(n.*(n+1));
      [oa, ob] = beam.getCoefficients(ci);

      if strcmpi(p.Results.basis, 'incoming')
        ai = oa .* (1i).^(n+1) .* Nn;
        bi = ob .* (1i).^n .* Nn;
      elseif strcmpi(p.Results.basis, 'outgoing')
        ai = oa .* (-1i).^(n+1) .* Nn;
        bi = ob .* (-1i).^n .* Nn;
      else
        error('ott:bsc:Bsc:efarfield:unknown_basis', ...
            'Unknown value for basis parameter');
      end

      % Get or calculate spherical harmonics
      [~, Ytheta, Yphi, data] = p.Results.data.evaluateYtp(...
          ci, rtp(2, :), rtp(3, :));

      % Re-arrange a/b for multiplication
      ai = permute(full(ai), [1, 3, 2]);
      bi = permute(full(bi), [1, 3, 2]);

      % Calculate field components
      Etheta = sum(ai .* Yphi + bi .* Ytheta, 1);
      Ephi = sum(-ai .* Ytheta + bi .* Yphi, 1);

      % Package output
      Ertp = [zeros(size(Etheta)); Etheta; Ephi];
      E = ott.utils.FieldVector(rtp, Ertp, 'spherical');
    end

    function [E, data] = efieldRtp(beam, rtp, varargin)
      % Calculate E-field around beam focus.
      %
      % If the radius is zero, sets the radius to 1e-100.
      %
      % Usage
      %   [E, data] = beam.efieldRtp(rtp, ...)
      %
      % Parameters
      %   - rtp (3xN numeric) -- Spherical coordinates for field calculation.
      %     Units of wavelength.  Packaged [r; theta; phi].
      %
      % Optional named parameters
      %   - data (ott.utils.VswfData) -- Field data for repeated field
      %     calculation.  Default is an empty VswfData structure.
      %
      %   - basis (enum) -- Vector spherical wave function basis to
      %     visualise.  Must be one of 'incoming', 'outgoing' or 'regular'.
      %     Default: ``'regular'``.

      p = inputParser;
      p.addParameter('data', ott.utils.VswfData(), ...
          @(x) isa(x, 'ott.utils.VswfData'));
      p.addParameter('basis', 'regular');
      p.parse(varargin{:});

      assert(ismatrix(rtp) && isnumeric(rtp) && size(rtp, 1) == 3, ...
          'rtp must be 3xN numeric matrix');

      % Multiply r by 2*pi
      rtp(1, :) = rtp(1, :) * 2*pi;

      % Replace near zero elements to avoid nans
      rtp(1, rtp(1, :) == 0) = 1e-100;

      ci = beam.getCombinedIndex();
      [n, ~] = ott.utils.combined_index(ci);
      Nn = 1./sqrt(n.*(n+1));

      % Get or calculate harmonics/Bessel data
      data = p.Results.data;
      [Y, Ytheta, Yphi, data] = data.evaluateYtp(ci, rtp(2, :), rtp(3, :));
      [hn, dhn, data] = data.evaluateBessel(n, rtp(1, :), p.Results.basis);

      % Get beam coefficients
      [ai, bi] = beam.getCoefficients(ci);
      ai = permute(full(ai), [1, 3, 2]);
      bi = permute(full(bi), [1, 3, 2]);

      % Calculate field components
      Er = sum(Nn.*n.*(n+1)./rtp(1, :).*hn.*Y.*bi, 1);
      Etheta = sum(Nn .* (ai .* Yphi .* hn + bi .* Ytheta .* dhn), 1);
      Ephi = sum(Nn .* (-ai .* Ytheta .* hn + bi .* Yphi .* dhn), 1);

      % Package output
      Ertp = [Er; Etheta; Ephi];
      E = ott.utils.FieldVector(rtp, Ertp, 'spherical');
    end

    function [H, data] = hfieldRtp(beam, rtp, varargin)
      % Calculate H-field around beam focus.
      %
      % If the radius is zero, sets the radius to 1e-100.
      %
      % Usage
      %   [E, data] = beam.hfieldRtp(rtp, ...)
      %
      % Parameters
      %   - rtp (3xN numeric) -- Spherical coordinates for field calculation.
      %     Units of wavelength.  Packaged [r; theta; phi].
      %
      % Optional named parameters
      %   - data (ott.utils.VswfData) -- Field data for repeated field
      %     calculation.  Default is an empty VswfData structure.
      %
      %   - basis (enum) -- Vector spherical wave function basis to
      %     visualise.  Must be one of 'incoming', 'outgoing' or 'regular'.
      %     Default: ``'regular'``.

      p = inputParser;
      p.addParameter('data', ott.utils.VswfData(), ...
          @(x) isa(x, 'ott.utils.VswfData'));
      p.addParameter('basis', 'regular');
      p.parse(varargin{:});

      assert(ismatrix(rtp) && isnumeric(rtp) && size(rtp, 1) == 3, ...
          'rtp must be 3xN numeric matrix');

      % Multiply r by 2*pi
      rtp(1, :) = rtp(1, :) * 2*pi;

      % Replace near zero elements to avoid nans
      rtp(1, rtp(1, :) == 0) = 1e-100;

      ci = beam.getCombinedIndex();
      [n, ~] = ott.utils.combined_index(ci);
      Nn = 1./sqrt(n.*(n+1));

      % Get or calculate harmonics/Bessel data
      data = p.Results.data;
      [Y, Ytheta, Yphi, data] = data.evaluateYtp(ci, rtp(2, :), rtp(3, :));
      [hn, dhn, data] = data.evaluateBessel(n, rtp(1, :), p.Results.basis);

      % Get beam coefficients
      [ai, bi] = beam.getCoefficients(ci);
      ai = permute(ai, [1, 3, 2]);
      bi = permute(bi, [1, 3, 2]);

      % Calculate field components
      Hr = sum(Nn.*n.*(n+1)./rtp(1, :).*hn.*Y.*ai, 1);
      Htheta = sum(Nn .* (bi .* Yphi .* hn + ai .* Ytheta .* dhn), 1);
      Hphi = sum(Nn .* (-bi .* Ytheta .* hn + ai .* Yphi .* dhn), 1);

      % Package output
      Hrtp = -1i*[Hr; Htheta; Hphi];
      H = ott.utils.FieldVector(rtp, Hrtp, 'spherical');
    end

    %
    % Sparsity functions
    %

    function b = issparse(beam)
      % Returns true if the VSWF data is sparse
      %
      % Usage
      %   b = issparse(beam)

      b = false(size(beam));
      for ii = 1:numel(beam)
        b(ii) = issparse(beam(ii).a) & issparse(beam(ii).b);
      end
    end

    function beam = full(beam)
      % Convert the VSWF data to a full matrix
      %
      % Usage
      %   beam = full(beam)

      ott.utils.nargoutCheck(beam, nargout);

      for ii = 1:numel(beam)
        beam(ii).a = full(beam(ii).a);
        beam(ii).b = full(beam(ii).b);
      end
    end

    function beam = sparse(beam)
      % Convert the VSWF data to a sparse matrix
      %
      % This function doesn't change the data.  For a method that removes
      % near-zeros elements, see :meth:`makeSparse`.
      %
      % Usage
      %   beam = sparse(beam)

      ott.utils.nargoutCheck(beam, nargout);

      for ii = 1:numel(beam)
        beam(ii).a = sparse(beam(ii).a);
        beam(ii).b = sparse(beam(ii).b);
      end
    end

    function beam = makeSparse(beam, varargin)
      % Make the beam sparse by removing near-zero power elements
      %
      % Usage
      %   beam = beam.makeSparse(...)
      %
      % Optional named arguments
      %   - AbsTol (numeric) -- Absolute tolerance for removing elements.
      %     Default: ``[]``.
      %
      %   - RelTol (numeric) -- Relative tolerance for removing elements.
      %     Power is relative to power in each beam.
      %     Default: ``1.0e-15``.
      %
      % If both AbsTol and RelTol are specified, only elements satisfying
      % both conditions are kept.

      ott.utils.nargoutCheck(beam, nargout);

      p = inputParser;
      p.addParameter('AbsTol', [], @isnumeric);
      p.addParameter('RelTol', 1.0e-15, @isnumeric);
      p.parse(varargin{:});

      for ii = 1:numel(beam)

        [oa, ob] = beam(ii).getCoefficients();
        pw = abs(oa).^2 + abs(ob).^2;

        non_zero = true(size(pw));
        if ~isempty(p.Results.AbsTol)
          non_zero = non_zero & pw > p.Results.AbsTol;
        end
        if ~isempty(p.Results.RelTol)
          non_zero = non_zero & pw > p.Results.RelTol*sum(pw, 1);
        end

        oa(~non_zero) = 0;
        ob(~non_zero) = 0;

        beam(ii).a = sparse(oa);
        beam(ii).b = sparse(ob);
      end
    end

    %
    % gpuArray functions
    %

    function beam = gpuArray(beam)
      % Copies the beam shape coefficient data to the GPU
      %
      % Usage
      %   beam = gpuArray(beam)

      ott.utils.nargoutCheck(beam, nargout);

      beam.a = gpuArray(beam.a);
      beam.b = gpuArray(beam.b);

    end

    function beam = gather(beam)
      % Apply `gather` to beam shape coefficient data.
      %
      % If the beam shape coefficient data is a gpuArray, returns a copy
      % of the beam in the local workspace with data transferred from the GPU.
      %
      % Usage
      %   beam = gather(beam)

      ott.utils.nargoutCheck(beam, nargout);

      beam.a = gather(beam.a);
      beam.b = gather(beam.b);

    end

    %
    % Nmax functions
    %

    function beam = setNmax(beam, nmax, varargin)
      % Resize the beam, with additional options
      %
      % Usage
      %   beam = beam.setNmax(nmax, ...)   or    beam.Nmax = nmax
      %   Set the Nmax, a optional warning is issued if truncation occurs.
      %
      % Optional named arguments
      %   - AbsTol (numeric) -- Absolute tolerance for removing elements.
      %     Default: ``[]``.
      %
      %   - RelTol (numeric) -- Relative tolerance for removing elements.
      %     Power is relative to power in each beam.
      %     Default: ``1.0e-15``.
      %
      %   - powerloss (enum) -- Action to take when beam power is lost.
      %     Can be one of 'ignore', 'warn' or 'error'.
      %     Default: ``'warn'``.

      ott.utils.nargoutCheck(beam, nargout);

      p = inputParser;
      p.addParameter('AbsTol', [], @isnumeric);
      p.addParameter('RelTol', 1.0e-15, @isnumeric);
      p.addParameter('powerloss', 'warn');
      p.parse(varargin{:});

      total_orders = ott.utils.combined_index(nmax, nmax);
      if size(beam.a, 1) > total_orders

        % Check AbsTol
        if ~isempty(p.Results.AbsTol) ...
            && ~strcmpi(p.Results.powerloss, 'ignore')

          pw = abs(beam.a).^2 + abs(beam.b).^2;
          last_idx = find(pw > p.Results.AbsTol, 1, 'last');
          if last_idx < total_orders
            if strcmpi(p.Results.powerloss, 'warn')
              warning('ott:beam:vswf:Bsc:setNmax:truncation', ...
                  ['Apparent errors of ' num2str(aapparent_error) ...
                      ', ' num2str(bapparent_error) ]);
            elseif strcmpi(p.Results.powerloss, 'error')
              error('ott:beam:vswf:Bsc:setNmax:truncation', ...
                  ['Apparent errors of ' num2str(aapparent_error) ...
                      ', ' num2str(bapparent_error) ]);
            else
              error('ott:beam:vswf:Bsc:setNmax:truncation', ...
                'powerloss should be one of ignore, warn or error');
            end
          end
        end

        mag0 = beam.power;

        beam.a = beam.a(1:total_orders, :);
        beam.b = beam.b(1:total_orders, :);

        % Check RelTol
        if ~strcmpi(p.Results.powerloss, 'ignore')

          mag1 = beam.power;
          apparent_error = abs( mag1 - mag0 )/mag0;

          if apparent_error > p.Results.RelTol
            if strcmpi(p.Results.powerloss, 'warn')
              warning('ott:beam:vswf:Bsc:setNmax:truncation', ...
                  ['Apparent errors of ' num2str(aapparent_error) ...
                      ', ' num2str(bapparent_error) ]);
            elseif strcmpi(p.Results.powerloss, 'error')
              error('ott:beam:vswf:Bsc:setNmax:truncation', ...
                  ['Apparent errors of ' num2str(aapparent_error) ...
                      ', ' num2str(bapparent_error) ]);
            else
              error('ott:beam:vswf:Bsc:setNmax:truncation', ...
                'powerloss should be one of ignore, warn or error');
            end
          end
        end
      elseif size(beam.a, 1) < total_orders
        beam.a(total_orders, :) = 0;
        beam.b(total_orders, :) = 0;
      end
    end

    function nbeam = shrinkNmax(beam, varargin)
      % Reduces the size of the beam while preserving power
      %
      % Usage
      %   beam = beam.shrinkNmax(...)
      %
      % Optional named arguments
      %   - AbsTol (numeric) -- Absolute tolerance for removing elements.
      %     Default: ``[]``.
      %
      %   - RelTol (numeric) -- Relative tolerance for removing elements.
      %     Power is relative to power in each beam.
      %     Default: ``1.0e-15``.
      %
      % If both AbsTol and RelTol are specified, only elements satisfying

      ott.utils.nargoutCheck(beam, nargout);

      p = inputParser;
      p.addParameter('AbsTol', [], @isnumeric);
      p.addParameter('RelTol', 1.0e-15, @isnumeric);
      p.parse(varargin{:});

      [oa, ob] = beam.getCoefficients();

      pw = abs(oa).^2 + abs(ob).^2;

      % Find last element that satisfies AbsTol
      if ~isempty(p.Results.AbsTol)
        last_idx = find(pw > p.Results.AbsTol, 1, 'last');
        minNmax = ott.utils.combined_index(last_idx) + 1;
      else
        minNmax = 0;
      end

      pw0 = [beam.power];

      for ii = minNmax:beam.Nmax

        total_orders = ott.utils.combined_index(ii, ii);
        na = oa(1:total_orders, :);
        nb = ob(1:total_orders, :);
        nbeam = ott.bsc.Bsc(na, nb);

        pw1 = nbeam.power;
        apparent_error = abs( pw1 - pw0 )/pw0;
        if apparent_error < p.Results.RelTol
          break;
        end
      end
    end

    %
    % Coefficient access
    %

    function beam = setCoefficients(beam, a, b)
      % Set the `a` and `b` coefficients.
      %
      % The beam coefficients can also be set directly by accessing the
      % `a` and `b` properties of the beam.
      %
      % Usage
      %   beam = beam.setCoefficients(a, b)
      %
      %   beam = beam.setCoefficients(ab)
      %   Set coefficients from a [a; b] vector.
      %
      %   beam = beam.setCoefficients(other_beam)
      %   Get the beam coefficients from another beam

      ott.utils.nargoutCheck(beam, nargout);

      if nargin == 2
        if isa(a, 'ott.beam.vswf.Bsc')
          b = a.b;
          a = a.a;
        else
          assert(isnumeric(a) && ismatrix(a), 'ab must be numeric matrix');
          assert(mod(size(a, 1), 2) == 0, 'ab must be 2NxM in size');
          b = a(end/2+1:end, :);
          a = a(1:end/2, :);
        end
      end

      assert(all(size(a) == size(b)), 'size of a and b must match');
      assert(nargout == 1, 'Expected one output from function');

      assert(isempty(a) || ...
          (size(a, 1) >= 3 && ...
          sqrt(size(a, 1)+1) == floor(sqrt(size(a, 1)+1))), ...
        'number of multipole terms must be empty, 3, 8, 15, 24, ...');

      beam.a = a;
      beam.b = b;
    end

    function varargout = getCoefficients(beam, ci)
      % Gets the beam `a` and `b` coefficients
      %
      % The `a` and `b` coefficients can also be retrieved by accessing the
      % `a` and `b` properties of the beam directly.
      % This function is useful for getting specific beam shape coefficients
      % or packaging the coefficients in specific ways.
      %
      % Usage
      %   ab = beam.getCoefficients() gets the beam coefficients packed
      %   into a single vector, suitable for multiplying by a T-matrix.
      %
      %   [a, b] = beam.getCoefficients() get the coefficients in two
      %   beam vectors.
      %
      %   [...] = beam.getCoefficients(ci) behaves as above but only returns
      %   the requested beam cofficients a(ci) and b(ci) in a dense format.

      % Get size of each beam vector
      na = zeros(1, numel(beam));
      nb = zeros(1, numel(beam));
      for ii = 1:numel(beam)
        na(ii) = numel(beam(ii).a);
        nb(ii) = numel(beam(ii).b);
      end

      % If ci omitted, return all a and b
      if nargin == 1
        ci = 1:max([na(:); nb(:)]);
      end

      % Get data from all beams
      oa = zeros(numel(ci), numel(beam), 'like', beam(1).a);
      ob = zeros(numel(ci), numel(beam), 'like', beam(1).b);
      for ii = 1:numel(beam)
        oa(ci <= na(ii), ii) = beam(ii).a(ci(ci <= na(ii)));
        ob(ci <= nb(ii), ii) = beam(ii).b(ci(ci <= nb(ii)));
      end

      % Package output
      if nargout == 1
        varargout{1} = [oa; ob];
      else
        [varargout{1:2}] = deal(oa, ob);
      end
    end

    function ci = getCombinedIndex(beam, varargin)
      % Get combined index for non-zero rows in all beams
      %
      % Usage
      %   ci = beam.getCombinedIndex(...)
      %
      % Optional named arguments
      %   - full (logical) -- If true, gets the combined index for every
      %     row (including empty rows).  Default: ``false``.

      p = inputParser;
      p.addParameter('full', false);
      p.parse(varargin{:});

      if p.Results.full

        % Get size of each beam vector
        na = zeros(1, numel(beam));
        nb = zeros(1, numel(beam));
        for ii = 1:numel(beam)
          na(ii) = numel(beam(ii).a);
          nb(ii) = numel(beam(ii).b);
        end

        % Construct full list of cis
        ci = (1:max([na; nb])).';

      else

        % Find rows with non-zero elements (works best with sparse)
        [oa, ob] = beam.getCoefficients();
        [rowIdx, ~] = find(oa ~= 0 | ob ~= 0);
        ci = unique(rowIdx);
      end
    end

    function [n, m] = getModeIndices(beam, varargin)
      % Get mode indices (useful for creating a dense beam vector)
      %
      % Usage
      %   [n, m] = beam.getModeIndices()
      %
      % Optional named arguments
      %   - full (logical) -- If true, gets the indices for every
      %     row (including empty rows).  Default: ``false``.

      p = inputParser;
      p.addParameter('full', false);
      p.parse(varargin{:});

      ci = beam.getCombinedIndex('full', p.Results.full);
      [n, m] = ott.utils.combined_index(ci);
    end

    %
    % Mathematical operations
    %

    function beam = plus(beam1, beam2)
      % Add beam shape coefficients of two beams
      %
      % Usage
      %   beam = beam1 + beam2;

      assert(isa(beam1, 'ott.bsc.Bsc'), 'beam1 must be a ott.bsc.Bsc');
      assert(isa(beam2, 'ott.bsc.Bsc'), 'beam2 must be a ott.bsc.Bsc');

      ott.utils.nargoutCheck(beam1, nargout);

      ci1 = beam1.getCombinedIndex('full', true);
      ci2 = beam2.getCombinedIndex('full', true);
      if numel(ci1) > numel(ci2)
        ci = ci1;
      else
        ci = ci2;
      end

      [a1, b1] = beam1.getCoefficients(ci);
      [a2, b2] = beam2.getCoefficients(ci);
      beam = ott.bsc.Bsc(a1+a2, b1+b2);
    end

    function beam = uminus(beam)
      % Unary minus of beam shape coefficient data
      %
      % Usage
      %   beam = -beam

      ott.utils.nargoutCheck(beam, nargout);

      beam.a = -beam.a;
      beam.b = -beam.b;
    end

    function beam = minus(beam1, beam2)
      % Minus operation on two beams
      %
      % Usage
      %   beam = beam1 - beam2

      assert(isa(beam1, 'ott.bsc.Bsc'), 'beam1 must be a ott.bsc.Bsc');
      assert(isa(beam2, 'ott.bsc.Bsc'), 'beam2 must be a ott.bsc.Bsc');

      ott.utils.nargoutCheck(beam1, nargout);

      beam = beam1 + (-beam2);
    end

    function beam = rdivide(beam, other)
      % Right array divide
      %
      % Usage
      %   beam = beam ./ other
      %
      % `other` can be a scalar or matrix with a compatible size.
      % Applies the operation to the whole coefficients vector, i.e.::
      %
      %   [a;b] = [a;b] ./ other

      ott.utils.nargoutCheck(beam, nargout);
      beam = beam.setCoefficients(beam.getCoefficients ./ other);
    end

    function beam = mrdivide(beam, other)
      % Right matrix divide
      %
      % Usage
      %   beam = beam / other
      %
      % Applies the operation to the whole coefficients vector, i.e.::
      %
      %   [a;b] = [a;b] / other

      ott.utils.nargoutCheck(beam, nargout);
      beam = beam.setCoefficients(beam.getCoefficients / other);
    end

    function beam = times(beam, rv)
      % Provides element-wise multiplication of BSC coefficients.
      %
      % Usage
      %   beam = beam .* row_vec
      %   Multiplies each beam by the elements of `row_vec`.

      assert(isa(beam, 'ott.bsc.Bsc'), 'first argument must be a Bsc');
      assert(isnumeric(rv) && ismatrix(rv) && size(rv, 1) == 1 ...
          && size(rv, 2) == numel(beam), ...
          'second argument must be row vector matching N-beams');

      beam.a = beam.a .* rv;
      beam.b = beam.b .* rv;
    end

    function beam = mtimes(a,b)
      % Provides beam matrix and scalar multiplication
      %
      % Usage
      %   beam = scalar * beam   or   beam = beam * scalar
      %   Scalar multiplication of beam shape coefficients.
      %
      %   beam = matrix * beam
      %   Matrix multiplication.  Matrix can either have the same
      %   number of columns as the `a` and `b` beam shape coefficients
      %   or half as many rows.  In other words, the resulting beam
      %   is either `[M*a; M*b]` or `M*[a;b]`.

      if isa(a, 'ott.bsc.Bsc')
        [oa, ob] = a.getCoefficients();
        beam = ott.bsc.Bsc(oa * b, ob * b);
      else
        [oa, ob] = b.getCoefficients();
        if size(a, 2) == 2*size(oa, 1)
          ab = a * [oa; ob];
          beam = ott.bsc.Bsc(ab(1:end/2, :), ...
              ab(1+end/2:end, :));
        else
          beam = ott.bsc.Bsc(a * oa, a * ob);
        end
      end
    end

    function beam = sum(beamin, dim)
      % Sum beam coefficients (similar to the builtin sum function).
      %
      % Usage
      %   beam = sum(beam, dim)
      %
      % Parameters
      %   - dim -- (Optional) dimension to sum over.  Default is the
      %     first non-singleton dimension.

      % Handle default value for dimension
      if nargin < 2
        dim = find(size(beamin) > 1, 1);
      end

      % Select the first row in our dimension
      subs = [repmat({':'},1,dim-1), 1, ...
        repmat({':'},1,ndims(beamin)-dim)];
      S = struct('type', '()', 'subs', {subs});
      beam = subsref(beamin, S);

      % Add each beam
      for ii = 2:size(beamin, dim)
        subs = [repmat({':'},1,dim-1), ii, ...
          repmat({':'},1,ndims(beamin)-dim)];
        S = struct('type', '()', 'subs', {subs});
        beam = beam + subsref(beamin, S);
      end
    end

    function beam = real(beam)
      % Extract real part of beam shape coefficients
      %
      % Usage
      %   beam = real(beam)

      [oa, ob] = beam.getCoefficients();
      beam = ott.bsc.Bsc(real(oa), real(ob));
    end

    function beam = imag(beam)
      % Extract imaginary part of beam shape coefficients
      %
      % Usage
      %   beam = imag(beam)

      [oa, ob] = beam.getCoefficients();
      beam = ott.bsc.Bsc(imag(oa), imag(ob));
    end

    function beam = abs(beam)
      % Calculate absolute value of BSC data
      %
      % Usage
      %   beam = abs(beam)

      [oa, ob] = beam.getCoefficients();
      beam = ott.bsc.Bsc(abs(oa), abs(ob));
    end

    %
    % Force calculation methods
    %

    function varargout = force(ibeam, sbeam)
      % Calculate change in linear momentum between beams.
      %
      % Usage
      %   force = ibeam.force(sbeam)
      %
      %   [fx, fy, fz] = ibeam.force(sbeam)
      %
      % To convert the force to SI units, divide by the speed in the medium
      % (assuming the beam power is in SI units).
      %
      % The scattered beam must be a total field beam (incoming+outgoing).
      %
      % This uses mathematical result of Farsund et al., 1996, in the form of
      % Chricton and Marsden, 2000, and our standard T-matrix notation S.T.
      % E_{inc}=sum_{nm}(aM+bN);

      % Get the abpq terms for the calculation
      [ai, bi, p, q, n, m, ...
        anp1, bnp1, pnp1, qnp1, ...
        amp1, bmp1, pmp1, qmp1, ...
        anp1mp1, bnp1mp1, pnp1mp1, qnp1mp1, ...
        anp1mm1, bnp1mm1, pnp1mm1, qnp1mm1] = ...
      ibeam.find_abpq_force_terms(sbeam);

      % Calculate the Z force
      Az=m./n./(n+1).*imag(-(ai).*conj(bi)+conj(q).*(p));
      Bz=1./(n+1).*sqrt(n.*(n-m+1).*(n+m+1).*(n+2)./(2*n+3)./(2*n+1)) ... %.*n
          .*imag(anp1.*conj(ai)+bnp1.*conj(bi)-(pnp1).*conj(p) ...
          -(qnp1).*conj(q));
      fz=2*sum(Az+Bz);

      % Calculate the XY force
      Axy=1i./n./(n+1).*sqrt((n-m).*(n+m+1)) ...
          .*(conj(pmp1).*q - conj(amp1).*bi - conj(qmp1).*p + conj(bmp1).*ai);
      Bxy=1i./(n+1).*sqrt(n.*(n+2))./sqrt((2*n+1).*(2*n+3)).* ... %sqrt(n.*)
          ( sqrt((n+m+1).*(n+m+2)) .* ( p.*conj(pnp1mp1) + q.* ...
          conj(qnp1mp1) -ai.*conj(anp1mp1) -bi.*conj(bnp1mp1)) + ...
          sqrt((n-m+1).*(n-m+2)) .* (pnp1mm1.*conj(p) + qnp1mm1.* ...
          conj(q) - anp1mm1.*conj(ai) - bnp1mm1.*conj(bi)) );

      fxy=sum(Axy+Bxy);
      fx=real(fxy);
      fy=imag(fxy);

      % Ensure things are full
      fx = full(fx);
      fy = full(fy);
      fz = full(fz);

      % Package output
      if nargout == 3
        varargout{1:3} = {fx, fy, fz};
      else
        varargout{1} = [fx(:) fy(:) fz(:)].';
      end
    end

    function varargout = torque(ibeam, sbeam)
      % Calculate change in angular momentum between beams
      %
      % Usage
      %   torque = ibeam.torque(sbeam)
      %
      %   [tx, ty, tz] = ibeam.torque(sbeam)
      %
      % % To convert torque/spin to SI units, divide by the angular frequency
      % (assuming the beam power is in SI units).
      %
      % The scattered beam must be a total field beam (incoming+outgoing).
      %
      % This uses mathematical result of Farsund et al., 1996, in the form of
      % Chricton and Marsden, 2000, and our standard T-matrix notation S.T.
      % E_{inc}=sum_{nm}(aM+bN);

      % Get the abpq terms for the calculation
      [ai, bi, p, q, n, m, ~, ~, ~, ~, ...
        amp1, bmp1, pmp1, qmp1] = ...
      ibeam.find_abpq_force_terms(sbeam);

      tz=sum(m.*(ai.*conj(ai)+bi.*conj(bi)-p.*conj(p)-q.*conj(q)));

      txy=sum(sqrt((n-m).*(n+m+1)).*(ai.*conj(amp1)+...
        bi.*conj(bmp1)-p.*conj(pmp1)-q.*conj(qmp1)));
      tx=real(txy);
      ty=imag(txy);

      % Ensure things are full
      tx = full(tx);
      ty = full(ty);
      tz = full(tz);

      % Package output
      if nargout == 3
        varargout{1:3} = {tx, ty, tz};
      else
        varargout{1} = [tx(:) ty(:) tz(:)].';
      end
    end

    function varargout = spin(ibeam, sbeam)
      % Calculate change in spin between beams
      %
      % Usage
      %   torque = ibeam.torque(sbeam)
      %
      %   [tx, ty, tz] = ibeam.torque(sbeam)
      %
      % To convert torque/spin to SI units, divide by the angular frequency
      % (assuming the beam power is in SI units).
      %
      % The scattered beam must be a total field beam (incoming+outgoing).
      %
      % This uses mathematical result of Farsund et al., 1996, in the form of
      % Chricton and Marsden, 2000, and our standard T-matrix notation S.T.
      % E_{inc}=sum_{nm}(aM+bN);

      % Get the abpq terms for the calculation
      [ai, bi, p, q, n, m, ...
        anp1, bnp1, pnp1, qnp1, ...
        amp1, bmp1, pmp1, qmp1, ...
        anp1mp1, bnp1mp1, pnp1mp1, qnp1mp1, ...
        anp1mm1, bnp1mm1, pnp1mm1, qnp1mm1] = ...
      ibeam.find_abpq_force_terms(sbeam);

      Cz=m./n./(n+1).*(-(ai).*conj(ai)+conj(q).*(q)-(bi).*conj(bi)+conj(p).*(p));
      Dz=-2./(n+1).*sqrt(n.*(n-m+1).*(n+m+1).*(n+2)./(2*n+3)./(2*n+1)) ...
            .*real(anp1.*conj(bi)-bnp1.*conj(ai)-(pnp1).*conj(q) ...
            +(qnp1).*conj(p));

      sz = sum(Cz+Dz);

      Cxy=1i./n./(n+1).*sqrt((n-m).*(n+m+1)).* ...
          (conj(pmp1).*p - conj(amp1).*ai + conj(qmp1).*q - conj(bmp1).*bi);
      Dxy=1i./(n+1).*sqrt(n.*(n+2))./sqrt((2*n+1).*(2*n+3)).* ...
            ( (sqrt((n+m+1).*(n+m+2)) .* ...
            ( p.*conj(qnp1mp1) - q.* conj(pnp1mp1) - ...
            ai.*conj(bnp1mp1) +bi.*conj(anp1mp1))) + ...
            (sqrt((n-m+1).*(n-m+2)) .* ...
            (pnp1mm1.*conj(q) - qnp1mm1.*conj(p) ...
            - anp1mm1.*conj(bi) + bnp1mm1.*conj(ai))) );

      sxy=sum(Cxy+Dxy);
      sy=real(sxy);
      sx=imag(sxy);

      % Ensure things are full
      sx = full(sx);
      sy = full(sy);
      sz = full(sz);

      % Package output
      if nargout == 3
        varargout{1:3} = {sx, sy, sz};
      else
        varargout{1} = [sx(:) sy(:) sz(:)].';
      end
    end

    %
    % Translation functions
    %

    function [beam, A, B] = translateZ(beam, z, varargin)
      % Apply translation along z axis
      %
      % Usage
      %   beam = beam.translateZ(z, ...)
      %
      %   [beam, A, B] = beam.translateZ(z, ...)
      %   Returns A, B for repeated translation calculations.
      %
      % Optional named arguments
      %   - Nmax (numeric) -- Requested minimum Nmax for translated beam.
      %     Default: ``beam.Nmax``.
      %
      %   - basis (enum) -- Type of translation, must be either
      %     'incoming', 'outgoing' or 'regular'.  Default is 'regular'
      %     which should be used for most types of translations.
      %     'outgoing' should be applied when the beam is a scattered beam.

      p = inputParser;
      p.addParameter('basis', 'regular');
      p.addParameter('Nmax', max([beam.Nmax]));
      p.parse(varargin{:});

      ott.utils.nargoutCheck(beam, nargout);

      % Determine beam type
      switch p.Results.basis
        case 'incoming'
          translation_type = 'sbesselh2';
        case 'outgoing'
          translation_type = 'sbesselh1';
        case 'regular'
          translation_type = 'sbesselj';
      end

      % Calculate tranlsation matrices
      [A, B] = ott.utils.translate_z(...
          [p.Results.Nmax, max([beam.Nmax])], ...
          z, 'type', translation_type);

      % Apply translation to beam
      beam = [A, B; B, A] * beam;

    end

  end

  methods (Hidden)
    function [beam, D] = rotateInternal(beam, R, varargin)
      % Apply a rotation to the beam shape coefficients.
      %
      % This function is called by the rotate* functions and is
      % typically not called directly.
      %
      % Usage
      %   [beam, D] = beam.rotateInternal(R)
      %   Returns the rotated beam and the wigner rotation matrix.
      %
      % Optional named arguments
      %   - Nmax (numeric) -- Requested minimum Nmax for rotated beam.
      %     Default: ``beam.Nmax``.

      p = inputParser;
      p.addParameter('Nmax', max([beam.Nmax]));
      p.parse(varargin{:});

      ott.utils.nargoutCheck(beam, nargout);

      assert(isnumeric(R) && ismatrix(R) && size(R, 1) == 3 ...
          && mod(size(R, 2), 3) == 0, ...
          'R must be 3x3N matrix');

      Nrots = size(R, 2)/3;
      Nbeams = numel(beam);

      assert(Nrots == 1 || Nbeams == 1 || Nrots == Nbeams, ...
          'Number of rotations must match number of beams or be scalar');

      Nwork = max([Nrots, Nbeams]);
      if Nrots > 1
        D = cell(1, Nrots);
        for ii = 1:Nrots
          D = ott.utils.wigner_rotation_matrix(...
              max([beam.Nmax, p.Results.Nmax]), R(:, (1:3) + (ii-1)*3));
        end
        
        if numel(beam) == 1
          ibeam = beam;
          for ii = 1:Nrots
            beam(ii) = D{ii} * ibeam;
          end
        else
          for ii = 1:Nrots
            beam(ii) = D{ii} * beam(ii);
          end
        end
      else
        D = {ott.utils.wigner_rotation_matrix(...
            max([beam.Nmax, p.Results.Nmax]), R)};
        beam = D{1} * beam;
      end

    end

    function [beam, Az, Bz, D] = translateXyzInternal(beam, xyz, varargin)
      % Apply translation to the beam shape coefficients.
      %
      % Applies rotations by first rotating the beam z-axis to align
      % to the translation axis, then translating along z, before
      % rotating back to the original orientation.
      %
      % This function uses units of wavelengths.
      %
      % This function is called by the rotate* functions and is
      % typically not called directly.
      %
      % Usage
      %   beam = beam.translateXyzInternal(xyz)
      %   Applies the rotation to the beam.
      %
      %   [beam, Az, Bz, D] = beam.translateXyzInternal(xyz)
      %   Returns Az, Bz and Wigner rotation matrix for repeated operations.
      %
      % Optional named arguments
      %   - Nmax (numeric) -- Requested minimum Nmax for translated beam.
      %     The Nmax limit is applied during the translation. The first
      %     rotation step uses the full Nmax, the last uses the new Nmax.
      %     Ignored when multiple outputs are requested.
      %     Default: ``beam.Nmax``.
      %
      %   - basis (enum) -- Type of translation, must be either
      %     'incoming', 'outgoing' or 'regular'.  Default is 'regular'
      %     which should be used for most types of translations.
      %     'outgoing' should be applied when the beam is a scattered beam.

      p = inputParser;
      p.addParameter('Nmax', max([beam.Nmax]));
      p.addParameter('basis', 'regular');
      p.parse(varargin{:});

      ott.utils.nargoutCheck(beam, nargout);

      assert(isnumeric(xyz) && ismatrix(xyz) && size(xyz, 1) == 3, ...
          'P must be 3xN numeric matrix');

      Nrots = size(xyz, 2);
      Nbeams = size(beam, 2);

      assert(Nrots == 1 || Nbeams == 1 || Nrots == Nbeams, ...
          'Number of positions must match number of beams or be scalar');

      oNmax = p.Results.Nmax;
      if nargout > 1
        oNmax = beam.Nmax;
      end

      % Check for work to do
      hasWork = false;
      for ii = 1:numel(Nrots)
        hasWork = hasWork | any(xyz(:, ii) ~= [0;0;0]);
      end

      Az = cell(1, Nrots);
      Bz = cell(1, Nrots);
      D = cell(1, Nrots);

      if hasWork

        ibsc = beam;

        for ii = 1:Nrots

          rtp = ott.utils.xyz2rtp(xyz(:, ii));
          R = ott.utils.rotz(rtp(3)*180/pi) * ott.utils.roty(rtp(2)*180/pi);

          if nargout > 1
            [newbeam, D{ii}] = ibsc.rotate(R);
            [newbeam, Az{ii}, Bz{ii}] = newbeam.translateZ(...
                rtp(1), 'Nmax', oNmax, 'basis', p.Results.basis);
            newbeam = D{ii}' * newbeam;
          else
            newbeam = ibsc.rotate(R);
            newbeam = newbeam.translateZ(rtp(1), ...
                'Nmax', oNmax, 'basis', p.Results.basis);
            newbeam = newbeam.rotate(R.');
          end

          beam(ii) = newbeam;
        end
      else
        beam = repmat(beam, 1, Nrots);
        Az = repmat({1}, 1, Nrots);
        Bz = repmat({0}, 1, Nrots);
        D = repmat({1}, 1, Nrots);
      end

      if Nrots == 1 && nargout > 1
        Az = Az{1};
        Bz = Bz{1};
        D = D{1};
      end
    end

    function [a, b, p, q, n, m, ...
      anp1, bnp1, pnp1, qnp1, ...
      amp1, bmp1, pmp1, qmp1, ...
      anp1mp1, bnp1mp1, pnp1mp1, qnp1mp1, ...
      anp1mm1, bnp1mm1, pnp1mm1, qnp1mm1] = ...
    find_abpq_force_terms(ibeam, sbeam)
      % Find the terms required for force/torque calculations
      %
      % From forcetorque function in OTTv1

      % Ensure beams are the same size
      if ibeam.Nmax > sbeam.Nmax
        sbeam.Nmax = ibeam.Nmax;
      elseif ibeam.Nmax < sbeam.Nmax
        ibeam.Nmax = sbeam.Nmax;
      end

      % Get the relevant beam coefficients
      [a, b] = ibeam.getCoefficients();
      [p, q] = sbeam.getCoefficients();
      [n, m] = ott.utils.combined_index((1:size(a, 1)).');

      nmax=ibeam.Nmax;

      b=1i*b;
      q=1i*q;

      addv=zeros(2*nmax+3,1);

      at=[a;repmat(addv, 1, size(a, 2))];
      bt=[b;repmat(addv, 1, size(b, 2))];
      pt=[p;repmat(addv, 1, size(p, 2))];
      qt=[q;repmat(addv, 1, size(q, 2))];

      ci=ott.utils.combined_index(n,m);

      %these preserve order and number of entries!
      np1=2*n+2;
      cinp1=ci+np1;
      cinp1mp1=ci+np1+1;
      cinp1mm1=ci+np1-1;
      cimp1=ci+1;
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      %this is for m+1... if m+1>n then we'll ignore!
      kimp=(m>n-1);

      anp1=at(cinp1, :);
      bnp1=bt(cinp1, :);
      pnp1=pt(cinp1, :);
      qnp1=qt(cinp1, :);

      anp1mp1=at(cinp1mp1, :);
      bnp1mp1=bt(cinp1mp1, :);
      pnp1mp1=pt(cinp1mp1, :);
      qnp1mp1=qt(cinp1mp1, :);

      anp1mm1=at(cinp1mm1, :);
      bnp1mm1=bt(cinp1mm1, :);
      pnp1mm1=pt(cinp1mm1, :);
      qnp1mm1=qt(cinp1mm1, :);

      amp1=at(cimp1, :);
      bmp1=bt(cimp1, :);
      pmp1=pt(cimp1, :);
      qmp1=qt(cimp1, :);

      amp1(kimp, :)=0;
      bmp1(kimp, :)=0;
      pmp1(kimp, :)=0;
      qmp1(kimp, :)=0;

      a=a(ci, :);
      b=b(ci, :);
      p=p(ci, :);
      q=q(ci, :);

    end
  end

  methods % Getters/setters
    function nmax = get.Nmax(beam)
      % Calculates Nmax from the current size of the beam coefficients
      nmax = ott.utils.combined_index(size(beam.a, 1));
    end
    function beam = set.Nmax(beam, nmax)
      % Resizes the beam vectors (a,b)
      beam = beam.setNmax(nmax);
    end

    function p = get.power(beam)
      % Calculate beam power from a/b
      [oa, ob] = beam.getCoefficients();
      p = gather(full(sum(abs(oa).^2 + abs(ob).^2, 1)));
    end
    function beam = set.power(beam, val)
      % Set the beam power
      beam = sqrt(val ./ beam.power) * beam;
    end

    function beam = set.a(beam, val)
      % Validate new a values
      if isempty(val)
        val = zeros(0, 1, 'like', val);
      end
      assert(iscolumn(val), ...
          'a must be a column vector');
      beam.a = val;
    end
    function beam = set.b(beam, val)
      % Validate new b values
      if isempty(val)
        val = zeros(0, 1, 'like', val);
      end
      assert(iscolumn(val), ...
          'b must be a column vector');
      beam.b = val;
    end
  end
end
