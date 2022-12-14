%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (c) 2014, 
% Chan-Byoung Chae (Yonsei University)
% H. Birkan YILMAZ (Yonsei University)
% All rights reserved.
%
% Updated and extended versions of this simulator can be found at:
% http://www.cmpe.boun.edu.tr/~yilmaz/
% http://www.cbchae.org/
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
% 1. Redistributions of source code must retain the above copyright
%    notice, this list of conditions and the following disclaimer.
% 2. All advertising materials mentioning features or use of this software
%    must display the following acknowledgement:
%    This product includes software developed by the Yonsei University.
% 4. Neither the name of the organization nor the
%    names of its contributors may be used to endorse or promote products
%    derived from this software without specific prior written permission.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [ nRx_wout_noise, n_destroy ] = CORE_sim_diffusion_3d_S2S_wAbsorption( ...
   tx_sym_seq, ...% Symbol sequence to modulate and transmit
   tx_node,    ...% Tx node properties
   rx_node,    ...% Rx node properties
   env_params, ...% Environment properties
   sim_params )   % Simulation parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This function simulates diffusion channel in 3D env
% with a spherical source and an absorbing receiver
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Parameters:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% tx_sym_seq               : Row vector with dimensions [1 x N_sym] 
%                            containing the symbols to transmit
%
% tx_node.center           : Center Coordinates of tx_node center
% tx_node.emission_point   : Coordinates of emission point
% tx_node.r_inMicroMeters  : Radius of tx_node
% tx_node.mod              : Modulator index (see block_modulate())
%
% rx_node.center           : Center Coordinates of rx_node center
% rx_node.r_inMicroMeters  : Radius of rx_node
% rx_node.p_react          : Reaction probability of receptors on Rx
% rx_node.demod            : DeModulator index (see block_demodulate())
%
% env_params.D_inMicroMeterSqrPerSecond   : Diffusion coefficient
% env_params.destruction_limit            : Destruction boundary
% 
% sim_params.delta_t                      : Simulation step time
% sim_params.molecules_perTs              : Number of molecules per Ts
% sim_params.ts_inSeconds                 : Symbol duration (Ts)
% sim_params.tss_inSeconds                : Sampling duration (Tss)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

p_react                 = rx_node.p_react;

if (p_react == 1)
   [ nRx_wout_noise, n_destroy ] = perfect_absorption(tx_sym_seq, tx_node, rx_node, env_params, sim_params );
else
   [ nRx_wout_noise, n_destroy ] = imperfect_absorption(tx_sym_seq, tx_node, rx_node, env_params, sim_params );
end

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [ nRx_wout_noise, n_destroy ] = perfect_absorption( ...
   tx_sym_seq, ...% Symbol sequence to modulate and transmit
   tx_node,    ...% Tx node properties
   rx_node,    ...% Rx node properties
   env_params, ...% Environment properties
   sim_params )   % Simulation parameters

n_sym                   = size(tx_sym_seq,2);

rx_r_inMicroMeters      = rx_node.r_inMicroMeters;
tx_r_inMicroMeters      = tx_node.r_inMicroMeters;
tx_emission_point       = tx_node.emission_point;

D                       = env_params.D_inMicroMeterSqrPerSecond;
destruction_limit_sq    = env_params.destruction_limit^2;

ts                      = sim_params.ts_inSeconds;
delta_t                 = sim_params.delta_t;
sim_time_inSeconds      = n_sym * ts;


% First find the number of simulation steps
sim_step_cnt = round(sim_time_inSeconds / delta_t);

% Standard deviation of step size of movement N(0,sigma)
sigma = (2*D*delta_t)^0.5;


rx_membrane_sq = (rx_r_inMicroMeters)^2;
tx_membrane_sq = (tx_r_inMicroMeters)^2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%   MODULATE  --> tx_timeline[mol_type_cnt x sim_step_cnt]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%   Tx timeline (each row corresponds different molecule type)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[tx_timeline, mol_type_cnt] = block_modulate(tx_sym_seq, tx_node, sim_params);

% Rx timeline Records the number of molecules at RECEIVER at each time step 
% Added DIFFERENT molecule TYPES by considering each row as another molecule type
nRx_wout_noise = zeros (mol_type_cnt, sim_step_cnt);

n_destroy = zeros (1, sim_step_cnt);

mol_position1 = zeros(0,3); 
mol_type1 = ones(0,1);
for t=1:sim_step_cnt
   % Check for Emission for EACH MOL_TYPE
   num_release = tx_timeline(:, t);
   
   if (sum(num_release) > 0)
      % Add new molecules to environment before moving them
      for ii=1:mol_type_cnt
          if (num_release(ii) > 0)
              mol_position1 = [ mol_position1 ; repmat(tx_emission_point, num_release(ii), 1) ];
              mol_type1 = [mol_type1; repmat([ii], num_release(ii), 1)];
          end
      end
   end
   
    % Propagate the molecules via diffusion
    mol_displace = normrnd (0, sigma, size(mol_position1,1), 3);
    mol_position2 =  mol_position1 + mol_displace;
    
    % Evaluate distance to Tx
    dist_sq_2_tx = sum(bsxfun(@minus, mol_position2, tx_node.center).^2, 2);
    
    inside_tx_mask = dist_sq_2_tx < tx_membrane_sq;
    % Roll back these movements
    mol_position2(inside_tx_mask, :) = mol_position1(inside_tx_mask, :);
    
    % Evaluate distance to Rx
    dist_sq_2_rcv = sum(bsxfun(@minus, mol_position2, rx_node.center).^2, 2);
    
    keep_mask = dist_sq_2_rcv < destruction_limit_sq;
    n_destroy(t) = n_destroy(t) + nnz(~keep_mask);
    %keep the ones indicated by the destruction mask (very far molecules are eliminated for efficiency)
    mol_position2 = mol_position2(keep_mask, :);
    dist_sq_2_rcv = dist_sq_2_rcv(keep_mask, :);
    mol_type1 = mol_type1(keep_mask);
    
    %outside the membrane (continues its life)
    outside_membrane_mask = dist_sq_2_rcv > rx_membrane_sq;
    
    mol_type_mask = zeros(size(mol_type1,1), mol_type_cnt);
    for ii=1:mol_type_cnt
        mol_type_mask(:,ii) = (mol_type1 == ii);
    end
    
    %reception (hit)
    for ii=1:mol_type_cnt
        nRx_wout_noise(ii, t) = nRx_wout_noise(ii, t) + nnz(~outside_membrane_mask & mol_type_mask(:,ii));
    end
    
    
    %keep the ones indicated by the outside membrane mask
    mol_position2 = mol_position2(outside_membrane_mask, :);
    mol_type1 = mol_type1(outside_membrane_mask);

    mol_position1 = mol_position2;
end


end





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [ nRx_wout_noise, n_destroy ] = imperfect_absorption( ...
   tx_sym_seq, ...% Symbol sequence to modulate and transmit
   tx_node,    ...% Tx node properties
   rx_node,    ...% Rx node properties
   env_params, ...% Environment properties
   sim_params )   % Simulation parameters

n_sym                   = size(tx_sym_seq,2);

p_react                 = rx_node.p_react;
rx_r_inMicroMeters      = rx_node.r_inMicroMeters;
tx_r_inMicroMeters      = tx_node.r_inMicroMeters;
tx_emission_point       = tx_node.emission_point;

D                       = env_params.D_inMicroMeterSqrPerSecond;
destruction_limit_sq    = env_params.destruction_limit^2;

ts                      = sim_params.ts_inSeconds;
delta_t                 = sim_params.delta_t;
sim_time_inSeconds      = n_sym * ts;

% First find the number of simulation steps
sim_step_cnt = round(sim_time_inSeconds / delta_t);

% Standard deviation of step size of movement N(0,sigma)
sigma = (2*D*delta_t)^0.5;


rx_membrane_sq = (rx_r_inMicroMeters)^2;
tx_membrane_sq = (tx_r_inMicroMeters)^2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%   MODULATE  --> tx_timeline[mol_type_cnt x sim_step_cnt]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%   Tx timeline (each row corresponds different molecule type)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[tx_timeline, mol_type_cnt] = block_modulate(tx_sym_seq, tx_node, sim_params);

% Rx timeline Records the number of molecules at RECEIVER at each time step 
% Added DIFFERENT molecule TYPES by considering each row as another molecule type
nRx_wout_noise = zeros (mol_type_cnt, sim_step_cnt);

n_destroy = zeros (1, sim_step_cnt);

mol_position1 = zeros(0,3); 
mol_type1 = ones(0,1);
for t=1:sim_step_cnt
   % Check for Emission for EACH MOL_TYPE
   num_release = tx_timeline(:, t);
   
   if (sum(num_release) > 0)
      % Add new molecules to environment before moving them
      for ii=1:mol_type_cnt
          if (num_release(ii) > 0)
              mol_position1 = [ mol_position1 ; repmat(tx_emission_point, num_release(ii), 1) ];
              mol_type1 = [mol_type1; repmat([ii], num_release(ii), 1)];
          end
      end
   end
   
    % Propagate the molecules via diffusion
    mol_displace = normrnd (0, sigma, size(mol_position1,1), 3);
    mol_position2 =  mol_position1 + mol_displace;
    
    % Evaluate distance to Tx
    dist_sq_2_tx = sum(bsxfun(@minus, mol_position2, tx_node.center).^2, 2);
    
    inside_tx_mask = dist_sq_2_tx < tx_membrane_sq;
    % Roll back these movements
    mol_position2(inside_tx_mask, :) = mol_position1(inside_tx_mask, :);
    
    % Evaluate distance to Rx
    dist_sq_2_rcv = sum(bsxfun(@minus, mol_position2, rx_node.center).^2, 2);
    
    keep_mask = dist_sq_2_rcv < destruction_limit_sq;
    n_destroy(t) = n_destroy(t) + nnz(~keep_mask);
    %keep the ones indicated by the destruction mask (very far molecules are eliminated for efficiency)
    mol_position1 = mol_position1(keep_mask, :); % FOR ROLL BACK of ~preact MOLECULES
    mol_position2 = mol_position2(keep_mask, :);
    dist_sq_2_rcv = dist_sq_2_rcv(keep_mask, :);
    mol_type1 = mol_type1(keep_mask);
    
    %outside the membrane (continues its life)
    outside_membrane_mask = dist_sq_2_rcv > rx_membrane_sq;
    
    mol_type_mask = zeros(size(mol_type1,1), mol_type_cnt);
    for ii=1:mol_type_cnt
        mol_type_mask(:,ii) = (mol_type1 == ii);
    end
    
    %react random for all "TODO: Optimize this point"
    react_mask = random('Uniform', 0, 1, size(outside_membrane_mask)) < p_react;
    
    %reception (hit)
    for ii=1:mol_type_cnt
        nRx_wout_noise(ii, t) = nRx_wout_noise(ii, t) + nnz(~outside_membrane_mask & mol_type_mask(:,ii) & react_mask);
    end
    
    %keep the ones indicated by the outside membrane mask or nonReacting from mol_position1
    mol_position2 = [ mol_position2(outside_membrane_mask, :); mol_position1(~outside_membrane_mask & ~react_mask, :)];
    mol_type1 = [ mol_type1(outside_membrane_mask) ; mol_type1(~outside_membrane_mask & ~react_mask) ];

    mol_position1 = mol_position2;
end

end

