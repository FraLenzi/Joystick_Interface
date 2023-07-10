library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity digilent_jstk2 is
	generic (
		DELAY_US		: integer := 25;    -- Delay (in us) between two packets
		CLKFREQ		 	: integer := 100_000_000;  -- Frequency of the aclk signal (in Hz)
		SPI_SCLKFREQ 	: integer := 66_666 -- Frequency of the SPI SCLK clock signal (in Hz)
	);
	Port ( 
		aclk 			: in  STD_LOGIC;
		aresetn			: in  STD_LOGIC;

		-- Data going TO the SPI IP-Core (and so, to the JSTK2 module)
		m_axis_tvalid	: out STD_LOGIC;
		m_axis_tdata	: out STD_LOGIC_VECTOR(7 downto 0);
		m_axis_tready	: in STD_LOGIC;

		-- Data coming FROM the SPI IP-Core (and so, from the JSTK2 module)
		-- There is no tready signal, so you must be always ready to accept and use the incoming data, or it will be lost!
		s_axis_tvalid	: in STD_LOGIC;
		s_axis_tdata	: in STD_LOGIC_VECTOR(7 downto 0);

		-- Joystick and button values read from the module
		jstk_x			: out std_logic_vector(9 downto 0);
		jstk_y			: out std_logic_vector(9 downto 0);
		btn_jstk		: out std_logic;
		btn_trigger		: out std_logic;

		-- LED color to send to the module
		led_r			: in std_logic_vector(7 downto 0);
		led_g			: in std_logic_vector(7 downto 0);
		led_b			: in std_logic_vector(7 downto 0)
	);
end digilent_jstk2;

architecture Behavioral of digilent_jstk2 is

	-- Code for the SetLEDRGB command, see the JSTK2 datasheet.
	constant CMDSETLEDRGB		: std_logic_vector(7 downto 0) := x"84";

	-- Do not forget that you MUST wait a bit between two packets. See the JSTK2 datasheet (and the SPI IP-Core README).
	-- Inter-packet delay plus the time needed to transfer 1 byte (for the CS de-assertion)
	constant DELAY_CYCLES		: integer := DELAY_US * (CLKFREQ / 1_000_000) + CLKFREQ / SPI_SCLKFREQ; --25*100 + 1500 = 4000 (4 ms); 
	
	------------------------------------------------------------

	-- These are examples of FSM states, you can use these if you want.

	type state_cmd_type is (WAIT_DELAY, SEND_CMD, SEND_RED, SEND_GREEN, SEND_BLUE, SEND_DUMMY);
	signal state_cmd				: state_cmd_type := WAIT_DELAY;
	-- signal next_state_cmd			: state_cmd_type;

	------------------------------------------------------------

	type state_sts_type is (GET_X_LSB, GET_X_MSB, GET_Y_LSB, GET_Y_MSB, GET_BUTTONS);
	signal state_sts				: state_sts_type := GET_X_LSB;
	-- signal next_state_sts			: state_sts_type;

	------------AUXILIARY SIGNALS-------------------------------
	signal counter					: integer range 0 to DELAY_CYCLES-1 := 0;
	
	signal x_value 					: std_logic_vector(jstk_x'RANGE) 	:= (Others => '0') ;
	signal y_value					: std_logic_vector(jstk_y'RANGE) 	:= (Others => '0');
	signal buttons					: std_logic_vector(1 downto 0)		:= (others => '0'); 
	signal data_exchange			: std_logic 						:= '0';

begin

	-----------------------DATA FLOW----------------------------


	with state_cmd select m_axis_tvalid <=
		'0' when WAIT_DELAY,
		'1' when SEND_CMD,
		'1' when SEND_RED,
		'1' when SEND_GREEN,
		'1' when SEND_BLUE,
		'1' when SEND_DUMMY,
		'0' when Others;


	--------------------PROCESS-----------------------------------
	
	Reset_logic : process (aclk, aresetn)
	begin
		if rising_edge(aclk) then
			if aresetn = '0' then
				m_axis_tvalid 	<= '0'; 
				state_cmd 		<= WAIT_DELAY;
				state_sts		<= GET_X_LSB;
				counter 		<= 0;
				data_exchange 	<= '0';
			end if;
		end if;
	end process;

	CMD_FSM_Next_State : process(aclk)
	begin
		if rising_edge(aclk) then	
			case state_cmd is
				
				when WAIT_DELAY =>

					if data_exchange = '1' then
						jstk_x		<= x_value;
						jstk_y		<= y_value;
						btn_jstk 	<= buttons(0);
						btn_trigger <= buttons(1);

						data_exchange <= '0';
					end if;
					if state_sts = GET_X_LSB then
						counter <= counter + 1;
						
					end if;
					if counter = DELAY_CYCLES-1 then
						state_cmd 	<= SEND_CMD;
						counter 	  	<= 0;
					end if;
					
				when SEND_CMD =>
					if m_axis_tready = '1' then
						m_axis_tdata 	<= CMDSETLEDRGB;
						state_cmd 		<= SEND_RED;
					end if;

				when SEND_RED =>
					if m_axis_tready = '1' then
						m_axis_tdata 	<= led_r;
						state_cmd 		<= SEND_GREEN;
					end if;

				when SEND_GREEN =>
					if m_axis_tready = '1' then
						m_axis_tdata 	<= led_g;
						state_cmd 		<= SEND_BLUE;
					end if;

				when SEND_BLUE =>
					if m_axis_tready = '1' then
						m_axis_tdata	<= led_b;
						state_cmd 		<= SEND_DUMMY;
					end if;

				when SEND_DUMMY =>	
					if m_axis_tready = '1' then
						m_axis_tdata 	<= (Others => '0');
						state_cmd 		<= WAIT_DELAY;
					end if;

			end case;
		end if;
	end process;

	
	STS_FSM_Next_State : process(aclk)
	begin
		if rising_edge(aclk) then
--			if state_cmd = WAIT_DELAY then
--				state_sts <= GET_X_LSB;
--			else
				case state_sts is 

				when GET_X_LSB =>
					if s_axis_tvalid = '1' then
						x_value(7 downto 0) <= s_axis_tdata;
						state_sts			<= GET_X_MSB;
					end if;	
				when GET_X_MSB =>
					if s_axis_tvalid = '1' then
						x_value(9 downto 8) <= s_axis_tdata;
						state_sts			<= GET_Y_LSB;
					end if;
				when GET_Y_LSB =>
					if s_axis_tvalid = '1' then 
						y_value(7 downto 0) <= s_axis_tdata(1 downto 0);
						state_sts			<= GET_Y_MSB;
					end if;
				when GET_Y_MSB =>
					if s_axis_tvalid = '1' then 
						y_value(9 downto 8) <= s_axis_tdata(1 downto 0);
						state_sts			<= GET_BUTTONS;
					end if;
				when GET_BUTTONS =>
					if s_axis_tvalid = '1' then
						buttons 		<= 	s_axis_tdata(1 downto 0);
						state_sts		<= GET_X_LSB;

						data_exchange <= '1';
					end if;
				end case;
--			end if;	
		end if;
	end process;

--	next_state_logic : process(aclk)
--	begin
--		if rising_edge(aclk) then
--			if state_sts /= next_state_sts AND state_cmd /= next_state_cmd then
--				state_sts <= next_state_sts;
--				state_cmd <= next_state_cmd;
--			end if;
--		end if;
--	end process;

end architecture;