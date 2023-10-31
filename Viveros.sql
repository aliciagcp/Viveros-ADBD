-- Crear tabla Vivero
CREATE TABLE Vivero (
	Nombre_Vivero VARCHAR(50) NOT NULL,
	Localizacion VARCHAR(50) NOT NULL,
	Telefono NUMERIC(15) NOT NULL,
	PRIMARY KEY(Nombre_Vivero)
);

-- Crear tabla Zonas
CREATE TABLE Zonas (
	Nombre_Zona Varchar(50) PRIMARY KEY NOT NULL,
   	Localizacion VARCHAR(50) NOT NULL,
    	Nombre_Vivero VARCHAR(50) REFERENCES Vivero ON DELETE CASCADE
);

-- Crear tabla Productos
CREATE TABLE Productos (
	Codigo_Producto NUMERIC(12) NOT NULL,
    	Nombre_Producto VARCHAR(50) NOT NULL,
    	Precio DECIMAL(7,2) NOT NULL,
    	Stock INT,
    	Nombre_Zona VARCHAR(50) REFERENCES Zonas ON DELETE CASCADE,
    	Nombre_Vivero VARCHAR(50) REFERENCES Vivero ON DELETE CASCADE,
    	PRIMARY KEY(Codigo_Producto, Nombre_Vivero)
);

-- Crear tabla Empleado
CREATE TABLE Empleado (
    	DNI_Empleado NUMERIC(8) PRIMARY KEY NOT NULL,
	Nombre_Empleado VARCHAR(50) NOT NULL,
	Numero_Cuenta NUMERIC(20) NOT NULL
);

-- Crear tabla ClientePlus
CREATE TABLE ClientePlus (
    	DNI_Cliente NUMERIC(8,0) PRIMARY KEY NOT NULL,
	Nombre_Cliente VARCHAR(50) NOT NULL,
	Volumen_Mensual DECIMAL(12,2) DEFAULT 0 CHECK (Volumen_Mensual >= 0),
	FI_Suscripcion DATE,
    	FF_Suscripcion DATE, 
    	Bonificacion NUMERIC(2,0) DEFAULT 10,
    	CONSTRAINT PD_CK CHECK (FF_Suscripcion >= FI_Suscripcion)
);

-- Crear tabla Vende
CREATE TABLE Vende (
	Codigo_Compra SERIAL PRIMARY KEY NOT NULL,
	Codigo_Producto NUMERIC(12,0)[],
	Precio_Final DECIMAL(7,2) NOT NULL DEFAULT 0.0,
	Cantidad INTEGER[] NOT NULL,
    	DNI_Cliente NUMERIC(8,0) REFERENCES ClientePlus ON DELETE SET DEFAULT,
    	DNI_Empleado NUMERIC(8,0) REFERENCES Empleado ON DELETE SET DEFAULT,
    	Nombre_Vivero VARCHAR(50) REFERENCES Vivero ON DELETE SET DEFAULT
);

-- Crear tabla Disponibilidad
CREATE TABLE Disponibilidad (
	DNI_Empleado NUMERIC(8) PRIMARY KEY REFERENCES Empleado ON DELETE CASCADE,
	Nombre_Vivero VARCHAR(50) REFERENCES Vivero ON DELETE SET DEFAULT,
	FI_Trabajo DATE,
    	FF_Trabajo DATE
);

-- Método para calcular el valor del precio final
CREATE OR REPLACE FUNCTION calcular_precio_final(
    _Codigo_Producto NUMERIC(12)[],
    _Cantidad INTEGER[],
    _DNI_Cliente NUMERIC(8),
    _Nombre_Vivero VARCHAR(50)
) RETURNS DECIMAL(7, 2) AS $$
DECLARE
    i integer;
    Precio_Final DECIMAL(7, 2) := 0.0;
BEGIN
    FOR i IN 1..array_length(_Codigo_Producto, 1) LOOP
        Precio_Final := Precio_Final + _Cantidad[i] * (SELECT Precio FROM Productos WHERE Codigo_Producto = _Codigo_Producto[i] AND Nombre_Vivero = _Nombre_Vivero);
    END LOOP;
    -- Si el cliente es cliente plus, se le calcula el precio final con la bonificacion.	
    IF _Codigo_Producto IS NOT NULL AND _DNI_Cliente IS NOT NULL THEN
    	Precio_Final := Precio_Final - ((Precio_Final * (SELECT Bonificacion FROM ClientePlus WHERE DNI_Cliente = _DNI_CLIENTE)) / 100);
    END IF;
    RETURN Precio_Final;
END;
$$ LANGUAGE plpgsql;

-- Método para calcular si una venta es realizada por un empleado válido. 
CREATE OR REPLACE FUNCTION check_empleado()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
        SELECT 1
        FROM Disponibilidad
        WHERE DNI_Empleado = NEW.DNI_Empleado
        AND Nombre_Vivero = NEW.Nombre_Vivero
    ) THEN
        RAISE EXCEPTION 'El empleado no se encuentra trabajando en el vivero.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_empleado
BEFORE INSERT ON Vende
FOR EACH ROW EXECUTE FUNCTION check_empleado();


-- Método que establece el precio final
CREATE OR REPLACE FUNCTION precio_final()
RETURNS TRIGGER AS $$
BEGIN
    NEW.Precio_Final = calcular_precio_final(NEW.Codigo_Producto, NEW.Cantidad, NEW.DNI_Cliente, NEW.Nombre_Vivero);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_precio_final
BEFORE INSERT ON Vende
FOR EACH ROW EXECUTE FUNCTION precio_final();

-- Método que comprueba la disponibilidad del empleado
CREATE OR REPLACE FUNCTION verificar_disponibilidad()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Disponibilidad
        WHERE DNI_Empleado = NEW.DNI_Empleado
        AND FF_Trabajo >= NEW.FI_Trabajo
    ) THEN
        RAISE EXCEPTION 'El empleado ya está asignado en un vivero durante ese período de tiempo';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_verificar_disponibilidad
BEFORE INSERT ON Disponibilidad
FOR EACH ROW EXECUTE FUNCTION verificar_disponibilidad();

-- Método para calcular la bonificación de un cliente
CREATE OR REPLACE FUNCTION asignar_bonificacion()
RETURNS TRIGGER AS $$
DECLARE 
  fecha_final date;
  volumen_mensual integer;
  bonificacion_final numeric(2,0);
BEGIN
   IF NEW.DNI_Cliente IS NOT NULL THEN 
    SELECT CP.FF_Suscripcion INTO fecha_final FROM ClientePlus CP WHERE CP.DNI_Cliente = NEW.DNI_Cliente;
    SELECT CP.Volumen_Mensual INTO volumen_mensual FROM ClientePlus CP WHERE CP.DNI_Cliente = NEW.DNI_Cliente;

    bonificacion_final := 10;

        IF volumen_mensual >= 500 THEN
            bonificacion_final := 75;
        ELSIF volumen_mensual >= 300 THEN
            bonificacion_final := 50;
        ELSIF volumen_mensual >= 100 THEN
            bonificacion_final := 25;
        ELSE
            bonificacion_final := 10;
        END IF;

    UPDATE ClientePlus
    SET Bonificacion = bonificacion_final
    WHERE DNI_Cliente = NEW.DNI_Cliente;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calcular_bonificacion
AFTER INSERT ON Vende
FOR EACH ROW EXECUTE FUNCTION asignar_bonificacion();

-- Método para calcular el volumen mensual de un cliente
CREATE OR REPLACE FUNCTION actualizar_volumen()
RETURNS TRIGGER AS $$
DECLARE 
  fecha_final DATE;
BEGIN
  SELECT FF_Suscripcion INTO fecha_final FROM ClientePlus WHERE DNI_Cliente = NEW.DNI_CLIENTE;

  IF fecha_final < NOW() AND NEW.DNI_Cliente IS NOT NULL THEN
    UPDATE ClientePlus
    SET Volumen_Mensual = 0
    WHERE DNI_Cliente = NEW.DNI_Cliente;
  ELSIF NEW.DNI_Cliente IS NOT NULL THEN
    UPDATE ClientePlus
    SET Volumen_Mensual = Volumen_Mensual + NEW.Precio_Final
    WHERE DNI_Cliente = NEW.DNI_Cliente;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_actualizar_volumen
AFTER INSERT ON Vende
FOR EACH ROW
EXECUTE FUNCTION actualizar_volumen();

-- Método para calcular el stock de un producto
CREATE FUNCTION actualizar_stock()
RETURNS TRIGGER AS $$
DECLARE
    i integer;
BEGIN
  IF NEW.Codigo_Producto IS NOT NULL THEN
  FOR i IN 1..array_length(NEW.Codigo_Producto, 1) LOOP
        UPDATE Productos
        SET Stock = Stock - NEW.Cantidad[i]
        WHERE Codigo_Producto = NEW.Codigo_Producto[i]
        AND Nombre_Vivero = NEW.Nombre_Vivero;  
    END LOOP;
   END IF;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_actualizar_stock
AFTER INSERT ON Vende
FOR EACH ROW
EXECUTE FUNCTION actualizar_stock();

-- Insertar valores en la tabla Vivero
INSERT INTO Vivero
VALUES ('Vivero1', 'Ubicacion1', 1234567890),
       ('Vivero2', 'Ubicacion2', 9876543210),
       ('Vivero3', 'Ubicacion3', 5555555555),
       ('Vivero4', 'Ubicacion4', 1111111111),
       ('Vivero5', 'Ubicacion5', 9999999999);

-- Insertar valores en la tabla Zonas
INSERT INTO Zonas
VALUES ('Zona1', 'Localizacion1', 'Vivero1'),
       ('Zona2', 'Localizacion2', 'Vivero2'),
       ('Zona3', 'Localizacion3', 'Vivero3'),
       ('Zona4', 'Localizacion4', 'Vivero4'),
       ('Zona5', 'Localizacion5', 'Vivero5');

-- Insertar valores en la tabla Productos
INSERT INTO Productos
VALUES (1, 'Producto1', 10.99, 100, 'Zona1', 'Vivero1'),
       (2, 'Producto2', 15.50, 200, 'Zona2', 'Vivero1'),
       (1, 'Producto1', 10.99, 100, 'Zona1', 'Vivero2'),
       (2, 'Producto2', 15.50, 200, 'Zona2', 'Vivero2'),
       (3, 'Producto3', 8.75, 150, 'Zona3', 'Vivero3'),
       (4, 'Producto4', 12.30, 120, 'Zona4', 'Vivero4'),
       (4, 'Producto4', 18.20, 180, 'Zona4', 'Vivero5'),
       (5, 'Producto5', 18.20, 180, 'Zona5', 'Vivero5');

-- Insertar valores en la tabla Empleado
INSERT INTO Empleado
VALUES (12345678, 'Empleado1', 123456789),
       (23456789, 'Empleado2', 987654321),
       (34567890, 'Empleado3', 111111111),
       (45678901, 'Empleado4', 222222222),
       (56789012, 'Empleado5', 333333333);

-- Insertar valores en la tabla ClientePlus
INSERT INTO ClientePlus (DNI_Cliente, Nombre_Cliente, FI_Suscripcion, FF_Suscripcion)
VALUES (11111111, 'Cliente1', '2023-10-31', '2023-11-30'),
       (22222222, 'Cliente2', '2023-10-31', '2023-11-30'),
       (33333333, 'Cliente3', '2023-10-31', '2023-11-30'),
       (44444444, 'Cliente4', '2023-10-31', '2023-11-30'),
       (55555555, 'Cliente5', '2023-10-31', '2023-11-30');

-- Insertar valores en la tabla Disponibilidad
INSERT INTO Disponibilidad(DNI_Empleado, Nombre_Vivero, FI_Trabajo, FF_Trabajo)
VALUES (12345678, 'Vivero1', '2023-11-01', '2023-11-05'),
       (23456789, 'Vivero2', '2023-11-02', '2024-11-02'),
       (34567890, 'Vivero3', '2023-09-11', '2023-11-15'),
       (45678901, 'Vivero4', '2023-10-16', '2023-11-20'),
       (56789012, 'Vivero5', '2023-01-21', '2025-12-31');

-- Insertar valores en la tabla Vende
INSERT INTO Vende (Codigo_Producto, Cantidad, DNI_Cliente, DNI_Empleado, Nombre_Vivero)
VALUES ('{1}', '{2}', 11111111, 12345678, 'Vivero1'),
       ('{2, 1}', '{4, 7}', 22222222, 23456789, 'Vivero2'),
       ('{3}', '{2}', 33333333, 34567890, 'Vivero3'),
       ('{4}', '{5}', 44444444, 45678901, 'Vivero4'),
       ('{5, 4}', '{3, 9}', 55555555, 56789012, 'Vivero5');
