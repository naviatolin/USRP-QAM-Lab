%% Clear
clear all
close all

%% OFDM Process

% Defining all constants.
block_len = 64; % number of channels in a block
prefix_len = 16; % length of the cyclic prefix
block_channel = 16; % number of blocks used to estimate channel
block_signal = 84; % number of blocks of actual data to calculate error
block_num = block_channel + block_signal; % 16 + 84 = 100

%% Generating the prefix
%{
    This generates the prefix that will be added to the cyclic prefixed
    data. There is also an alternating sequence appended to the beginning 6
    times in order to accurately find the beginning of the data. There were
    issues previously with just using the preamble to find the beginning of
    the data, so this alternating sequence helps this happen.
%}
block_preamble = 3; % number of blocks in preamble
lts = gen_data(1, block_len); % 1x64

% Constructing the preamble by copying the LTS 3 times.
preamble = [];
for i = 1:block_preamble
    preamble = [preamble lts];
end

% Append the alternating signal.
delay_find = [1 -1 1 -1 1 -1 1 -1 1 -1];
finder_sequence = [delay_find delay_find delay_find delay_find delay_find delay_find];
preamble = [finder_sequence preamble];
%% Generating data to send.
%{
    This generates all data that will have the cyclic prefix added to it. 
    This includes the data used to estimate the channel and the actual data
    that will be sent.
%}
tx = gen_data(block_num, block_len);

%% Splitting the blocks into channel estimation and signal portions.
end_channel = block_channel*block_len; % index seperating the channel estimation blocks from the data blocks

tx_channel_blocks = tx(1:end_channel); % 16 * 64 = 1024
tx_signal_blocks = tx(end_channel + 1:end); % 84 * 64 = 5376

%% Adding the cyclic prefix to the signal and converting to the time domain.
%{
    For each block, the IDFT is taken and then the cyclic prefix is added.
    The cyclic prefix length is 16. So, the final block length will be
    80. Since 100 blocks are being sent, the final length will be 8000.
%}
tx_prefixed = prefix_long(tx, block_len, prefix_len, block_num);

%% Appending the preamble to the prefixed data.
tx_preambled = [preamble tx_prefixed];

%% Passing the signal through the channel.
rx_unprocessed = nonflat_channel_timing_error(tx_preambled.').';

%% Accounting for the delay.
%{
    This delay will remove any unnecessary bits before the start of the
    signal. The final length may not be the same length as what was
    originally sent because the receiver doesn't stop immediately after the
    signal stops.
%}
delay = find_delay(rx_unprocessed, finder_sequence) + length(finder_sequence); % should be 69
rx_delay = rx_unprocessed(delay:end);

%% Adjusting for the fdelta.
%{
    The second half of the Schmidl Cox algorithm is implemented here. The
    frequency shift can be accounted for here by finding the different
    between the sent prefix and the received prefix.
%}
% Seperating the first and second blocks out.
preamble_len = block_preamble * block_len; % 1x192
actual_signal_start = preamble_len + 1; % should be 193

% Seperating the preamble from the actual data.
rx_preamble_only = rx_delay(1:preamble_len); % 1x192
rx_without_preamble = rx_delay(actual_signal_start : end);

first_lts_start = block_len + 1; % should be 65
first_lts_end = (block_len * 2); % should be 128
second_lts_start = first_lts_end + 1; % should be 129
second_lts_end = (block_len * 3); % should be 192

first_lts = rx_preamble_only(first_lts_start : first_lts_end); % 1x64
second_lts = rx_preamble_only(second_lts_start : second_lts_end); % 1x64

% Calculating F_delta.
f_sum = 0;
divided = second_lts ./ first_lts; % 1x64
f_angle = angle(divided); % 1x64
f_sum = sum(f_angle);
f_delta = f_sum / block_len / block_len;

% Apply F_delta.
indices = [1:length(rx_without_preamble)];
exponents = exp(-1 * 1j * f_delta * indices);
rx_freq_adjusted = rx_without_preamble .* exponents;
%% Removing the cyclic prefix and converting to the frequency domain.
%{
    For each block, the prefix is removed and the DFT is taken.
    The final length of the signal will be the total block number
    multiplied by 64. The final length will be 6400 as there are 100
    blocks.
%}
rx_cropped = crop_long(rx_freq_adjusted, block_len, prefix_len, block_num); 

%% Splitting the received signal into the channel estimation and signal portions.
rx_channel_blocks = rx_cropped(1:end_channel);
rx_signal_blocks = rx_cropped(end_channel+1:end);

%% Estimating the channel.
multiple_channel_estimations = rx_channel_blocks./tx_channel_blocks;
h_stacked = reshape(multiple_channel_estimations, [block_len, block_channel]).';

H = mean(h_stacked);

%% Estimating the data sent. 
estimated_signal = estimate_signal(H, rx_signal_blocks, block_signal);

%% Calculating the error.
%{
    Unnecessary complex components are removed. The sign is taken to allow
    only -1 and 1 values. This is in order to estimate the error correctly.
%}
X_hat = sign(real(estimated_signal));

error = compute_error(X_hat, tx_signal_blocks)

%% Figures created.
% Constellation plot of the data after receiving it.
figure
hold on
plot(rx_without_preamble, '.');
plot(estimated_signal, '.');
xlabel('Real')
ylabel('Imaginary')
legend('Before Frequency Correction', 'After Frequency Correction');

% Example block from the signal. 
figure
hold on
stairs(tx_signal_blocks(1:64), 'LineWidth', 1, 'Color', 'red')
stairs(estimated_signal(1:64), 'LineWidth', 1, 'Color', 'blue')
ylim([-1.35 1.35])
xlabel('Frequency Channels')
ylabel('Data')
legend('Transmitted Data', 'Received Data');
hold off
