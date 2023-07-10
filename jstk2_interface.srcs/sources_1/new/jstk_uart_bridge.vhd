library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity jstk_uart_bridge is
	generic (
		HEADER_CODE		: std_logic_vector(7 downto 0) := x"c0"; 	-- Header of the packet
		TX_DELAY		: positive := 1_000_000;    				-- Pause (in clock cycles) between two packets
		JSTK_BITS		: integer range 1 to 7 := 7    				-- Number of bits of the joystick axis to transfer to the PC
	);
	Port ( 
		aclk 			: in  std_logic;
		aresetn			: in  std_logic;

		-- Data going TO the PC (i.e., joystick position and buttons state)
		m_axis_tvalid	: out std_logic;
		m_axis_tdata	: out std_logic_vector(7 downto 0);
		m_axis_tready	: in std_logic;

		-- Data coming FROM the PC (i.e., LED color)
		s_axis_tvalid	: in std_logic;
		s_axis_tdata	: in std_logic_vector(7 downto 0);
		s_axis_tready	: out std_logic;

		jstk_x			: in std_logic_vector(9 downto 0);
		jstk_y			: in std_logic_vector(9 downto 0);
		btn_jstk		: in std_logic;
		btn_trigger		: in std_logic;

		led_r			: out std_logic_vector(7 downto 0);
		led_g			: out std_logic_vector(7 downto 0);
		led_b			: out std_logic_vector(7 downto 0)
	);
end jstk_uart_bridge;

architecture Behavioral of jstk_uart_bridge is

	-- These are examples of FSM states, you can use these if you want.

	type tx_state_type is (DELAY, SEND_HEADER, SEND_JSTK_X, SEND_JSTK_Y, SEND_BUTTONS);
	signal tx_state			: tx_state_type;
--	signal tx_next_state	: tx_state_type;

	--------------------------------------------
	
	type rx_state_type is (IDLE, GET_HEADER, GET_LED_R, GET_LED_G, GET_LED_B);
	signal rx_state			: rx_state_type;
--	signal rx_next_state	: rx_state_type;

--		We sample the RGB
	signal r_reg			: std_logic_vector(led_r'RANGE);
	signal g_reg			: std_logic_vector(led_g'RANGE);
	signal b_reg			: std_logic_vector(led_b'RANGE);
	
--		We sample the joystick position and buttons	
	signal jstk_x_reg		: std_logic_vector(m_axis_tdata'RANGE)	:= (Others=>'0');  
	signal jstk_y_reg		: std_logic_vector(m_axis_tdata'RANGE)	:= (Others=>'0');
	signal btn_reg			: std_logic_vector(m_axis_tdata'RANGE)	:= (Others=>'0'); -- change only bit 1 and bit 0 (so '000000' header is always preserved)


	signal counter 			: integer range 0 to TX_DELAY-1			:= 0;

begin

	reset_logic : process (aclk)
	begin
		if rising_edge(aclk) then
			if aresetn = '0' then
				m_axis_tvalid 	<= '0';
				s_axis_tready	<= '0';
				
			end if;
		end if;
	end process;


-- Transmission process
	tx_process : process(aclk)
	begin
		case tx_state is
			when DELAY =>

				counter <= counter + 1;
				
				if counter = TX_DELAY-1 then

					jstk_x_reg(JSTK_BITS-1 DOWNTO 0) 	<= jstk_x(9 DOWNTO 9-JSTK_BITS+1);
					jstk_y_reg(JSTK_BITS-1 DOWNTO 0)	<= jstk_x(9 DOWNTO 9-JSTK_BITS+1);
					btn_reg(1 DOWNTO 0) 				<= btn_trigger & btn_jstk;

					counter 	<= 0;

					m_axis_tvalid <= '1';				
					tx_state 	<= SEND_HEADER;
					
				end if;

			when SEND_HEADER =>
				if m_axis_tready = '1' then
					m_axis_tdata <= HEADER_CODE;
					tx_state <= SEND_JSTK_X;
				end if;

			when SEND_JSTK_X =>
				if m_axis_tready = '1' then
					m_axis_tdata <= jstk_x_reg;
					tx_state <= SEND_JSTK_Y;
				end if;

			when SEND_JSTK_Y => 
				if m_axis_tready = '1' then				
					m_axis_tdata <= jstk_y_reg;
					tx_state <= SEND_BUTTONS;
				end if;
				
			when SEND_BUTTONS =>			
				if m_axis_tready = '1' then
					m_axis_tdata <= btn_reg;
					tx_state <= DELAY;
					m_axis_tvalid <= '0';								
				end if;
		end case;
	end process;

end architecture;