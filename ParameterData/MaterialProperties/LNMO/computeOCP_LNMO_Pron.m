function OCP = computeOCP_LNMO_Pron(theta)
% Data from
%  @article{Pron_2019, title={Electrochemical Characterization and Solid Electrolyte Interface Modeling of LiNi0.5Mn1.5O4-Graphite Cells}, volume={166}, ISSN={1945-7111}, url={http://dx.doi.org/10.1149/2.0941910jes}, DOI={10.1149/2.0941910jes}, number={10}, journal={Journal of The Electrochemical Society}, publisher={The Electrochemical Society}, author={Pron, Vittorio Giai and Versaci, Daniele and Amici, Julia and Francia, Carlotta and Santarelli, Massimo and Bodoardo, Silvia}, year={2019}, pages={A2255–A2263} }

% referenceTemperature = 293.15;  % [K]

    
    OCP_table = [ [0.0189085, 4.85689]; ...
                  [0.0291227, 4.83565]; ...
                  [0.0393364, 4.82253]; ...
                  [0.0484801, 4.81472]; ...
                  [0.0597759, 4.80785]; ...
                  [0.0700003, 4.80348]; ...
                  [0.0802146, 4.80067]; ...
                  [0.0904282, 4.79817]; ...
                  [0.100654 , 4.79629]; ...
                  [0.110868 , 4.79442]; ...
                  [0.121081 , 4.79317]; ...
                  [0.131306 , 4.79161]; ...
                  [0.141521 , 4.79067]; ...
                  [0.151746 , 4.79036]; ...
                  [0.16196  , 4.7888]; ...
                  [0.172173 , 4.78786]; ...
                  [0.182398 , 4.78661]; ...
                  [0.192613 , 4.78598]; ...
                  [0.202836 , 4.78536]; ...
                  [0.213052 , 4.78505]; ...
                  [0.223266 , 4.7838]; ...
                  [0.23349  , 4.78349]; ...
                  [0.243705 , 4.78317]; ...
                  [0.25393  , 4.78255]; ...
                  [0.264143 , 4.78161]; ...
                  [0.274358 , 4.78099]; ...
                  [0.284582 , 4.78068]; ...
                  [0.294796 , 4.78005]; ...
                  [0.305011 , 4.77974]; ...
                  [0.315236 , 4.77818]; ...
                  [0.32545  , 4.77786]; ...
                  [0.335675 , 4.77693]; ...
                  [0.345888 , 4.7763]; ...
                  [0.356104 , 4.77568]; ...
                  [0.366327 , 4.77537]; ...
                  [0.376542 , 4.77443]; ...
                  [0.386766 , 4.7738]; ...
                  [0.396981 , 4.77318]; ...
                  [0.407195 , 4.77287]; ...
                  [0.41742  , 4.7713]; ...
                  [0.427633 , 4.77068]; ...
                  [0.437859 , 4.76724]; ...
                  [0.448072 , 4.76256]; ...
                  [0.458287 , 4.75725]; ...
                  [0.468511 , 4.75381]; ...
                  [0.478726 , 4.75256]; ...
                  [0.48894  , 4.75163]; ...
                  [0.499164 , 4.75038]; ...
                  [0.509379 , 4.75006]; ...
                  [0.519798 , 4.74944]; ...
                  [0.529818 , 4.7485]; ...
                  [0.540032 , 4.74788]; ...
                  [0.550257 , 4.74788]; ...
                  [0.560471 , 4.74819]; ...
                  [0.570694 , 4.74694]; ...
                  [0.58091  , 4.74663]; ...
                  [0.591124 , 4.74632]; ...
                  [0.601348 , 4.74632]; ...
                  [0.611562 , 4.74538]; ...
                  [0.621983 , 4.74507]; ...
                  [0.632002 , 4.74507]; ...
                  [0.642216 , 4.74351]; ...
                  [0.652441 , 4.74382]; ...
                  [0.662654 , 4.74319]; ...
                  [0.67288  , 4.74226]; ...
                  [0.683094 , 4.74038]; ...
                  [0.693416 , 4.74038]; ...
                  [0.703533 , 4.73788]; ...
                  [0.713747 , 4.7357]; ...
                  [0.723961 , 4.73257]; ...
                  [0.734186 , 4.73007]; ...
                  [0.7444   , 4.72726]; ...
                  [0.754625 , 4.7257]; ...
                  [0.764839 , 4.7257]; ...
                  [0.775053 , 4.7257]; ...
                  [0.785278 , 4.72476]; ...
                  [0.805716 , 4.72008]; ...
                  [0.815931 , 4.71571]; ...
                  [0.826145 , 4.70977]; ...
                  [0.83637  , 4.70134]; ...
                  [0.846583 , 4.69072]; ...
                  [0.856808 , 4.6801]; ...
                  [0.867022 , 4.66511]; ...
                  [0.877237 , 4.64324]; ...
                  [0.887461 , 4.61138]; ...
                  [0.897677 , 4.56453]; ...
                  [0.907895 , 4.49612]; ...
                  [0.918114 , 4.37087]; ...
                  [0.928332 , 4.27123]; ...
                  [0.93855  , 4.19752]; ...
                  [0.948768 , 4.14411]; ...
                  [0.958986 , 4.10381]; ...
                  [0.969204 , 4.06852]; ...
                  [0.979423 , 4.03322]; ...
                  [0.989642 , 3.98918]; ...
                  [0.99986  , 3.55626]];

    OCP = interpTable(OCP_table(:, 1), OCP_table(:, 2), theta);

end


























