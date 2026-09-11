%% fft_verify.m
% Verifies your 32-point DIT FFT Verilog hardware output against MATLAB's
% built-in FFT.
%
% This reads THREE plain text files, all in the same "one binary word per
% line" format as your existing in_ram.txt:
%   in_ram.txt       - the input samples (already exists, feeds $readmemb)
%   output_real.txt  - real part of each FFT output bin  (NEW)
%   output_imag.txt  - imag part of each FFT output bin  (NEW)
%
% output_real.txt / output_imag.txt are written automatically by the
% updated top_tb.v at the end of the simulation (it now dumps out0_r..
% out31_i to those files and then calls $finish). So the flow is simply:
%   1. Run RTL Simulation in Quartus (or `do top_run_msim_rtl_verilog.do`
%      in Questa) like normal.
%   2. The simulation now stops itself once it has written the two output
%      files, in the same folder Questa runs from (simulation/questa/).
%   3. Run this MATLAB script, pointing OUT_REAL_PATH/OUT_IMAG_PATH at
%      that folder -- no copy-pasting values by hand anymore.

clear; clc; close all;

%% ---------------- USER SETTINGS ----------------
IN_RAM_PATH   = 'C:/Users/DELL/AppData/Local/quartus/res_proj/FFT_dit/in_ram.txt';
OUT_REAL_PATH = 'C:/Users/DELL/AppData/Local/quartus/res_proj/FFT_dit/simulation/questa/output_real.txt';
OUT_IMAG_PATH = 'C:/Users/DELL/AppData/Local/quartus/res_proj/FFT_dit/simulation/questa/output_imag.txt';''    % written by top_tb.v -- imag part

N           = 32;   % FFT length
Q           = 8;    % fractional bits -> Q8.8 fixed point (matches top_tb: N=16, Q=8)
WORD_BITS   = 16;   % total bit width of each sample/output word

% Tolerance on |hw - ref| per bin, in the same fixed-point units as the
% signals themselves. A few hundredths to ~0.1 is normal rounding noise
% from quantizing the twiddle factors to Q8.8 across 5 butterfly stages;
% anything much larger (order 1 or more) points to a real bug.
TOLERANCE = 0.5;
%% ------------------------------------------------

%% 1. Load the input vector actually used by the testbench
x = read_fixed_point_file(IN_RAM_PATH, N, Q, WORD_BITS);
fprintf('Input vector x (decoded from %s):\n', IN_RAM_PATH);
disp(x);

%% 2. Golden reference FFT (MATLAB built-in, full floating point)
X_ref = fft(x, N);

figure('Name', 'Reference FFT');
subplot(2,1,1);
stem(0:N-1, abs(X_ref), 'filled');
title('|X_{ref}(k)|  --  MATLAB fft(x)');
xlabel('bin k'); ylabel('magnitude'); grid on;

subplot(2,1,2);
stem(0:N-1, angle(X_ref), 'filled');
title('phase(X_{ref}(k))');
xlabel('bin k'); ylabel('radians'); grid on;

fprintf('\nBin |  Real X_ref |  Imag X_ref\n');
for k = 0:N-1
    fprintf('%3d | %11.4f | %11.4f\n', k, real(X_ref(k+1)), imag(X_ref(k+1)));
end

%% 3. Load the hardware output and compare
haveHwFiles = isfile(OUT_REAL_PATH) && isfile(OUT_IMAG_PATH);

if haveHwFiles
    hw_real = read_fixed_point_file(OUT_REAL_PATH, N, Q, WORD_BITS);
    hw_imag = read_fixed_point_file(OUT_IMAG_PATH, N, Q, WORD_BITS);
    X_hw = hw_real + 1j * hw_imag;

    err = X_hw - X_ref;
    abs_err = abs(err);
    max_err = max(abs_err);
    mean_err = mean(abs_err);

    fprintf('\nBin |   HW Real  |   HW Imag  |  Ref Real  |  Ref Imag  |  |error|\n');
    for k = 0:N-1
        fprintf('%3d | %10.4f | %10.4f | %10.4f | %10.4f | %8.4f\n', ...
            k, real(X_hw(k+1)), imag(X_hw(k+1)), ...
            real(X_ref(k+1)), imag(X_ref(k+1)), abs_err(k+1));
    end
    fprintf('\nMax  |error| across all bins : %.6f\n', max_err);
    fprintf('Mean |error| across all bins : %.6f\n', mean_err);

    if max_err < TOLERANCE
        fprintf('\nPASS -- hardware FFT matches the MATLAB reference within tolerance (%.3f).\n', TOLERANCE);
    else
        fprintf('\nFAIL -- error exceeds tolerance (%.3f). Check the bins with the largest |error| above.\n', TOLERANCE);
    end

    figure('Name', 'Hardware vs Reference');
    subplot(2,1,1);
    stem(0:N-1, abs(X_ref), 'filled'); hold on;
    stem(0:N-1, abs(X_hw), 'x');
    legend('|X_{ref}|', '|X_{hw}|'); grid on;
    title('Magnitude: hardware vs reference');
    xlabel('bin k');

    subplot(2,1,2);
    stem(0:N-1, abs_err, 'filled');
    yline(TOLERANCE, 'r--', 'tolerance');
    title('|Error| per bin');
    xlabel('bin k'); ylabel('|X_{hw} - X_{ref}|'); grid on;
else
    fprintf('\n%s / %s not found next to this script.\n', OUT_REAL_PATH, OUT_IMAG_PATH);
    fprintf('Run the simulation first (updated top_tb.v writes these automatically and then\n');
    fprintf('calls $finish), then either re-run this script from that folder or update\n');
    fprintf('OUT_REAL_PATH/OUT_IMAG_PATH to point at simulation/questa/ in your project.\n');
end

%% ---------------- Local functions ----------------
function x = read_fixed_point_file(path, N, Q, WORD_BITS)
    % Reads N lines of WORD_BITS-wide binary text (e.g. "0000000100000000")
    % and decodes each as a signed Q(WORD_BITS-Q).Q fixed-point number.
    fid = fopen(path, 'r');
    if fid == -1
        error('Could not open "%s".', path);
    end
    raw = textscan(fid, '%s');
    fclose(fid);
    lines = raw{1};
    if numel(lines) ~= N
        error('%s has %d lines, expected %d.', path, numel(lines), N);
    end
    x = zeros(1, N);
    for k = 1:N
        bits = lines{k};
        val = bin2dec(bits);
        if bits(1) == '1'          % sign bit set -> negative, two's complement
            val = val - 2^WORD_BITS;
        end
        x(k) = val / 2^Q;
    end
end
